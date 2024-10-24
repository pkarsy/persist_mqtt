# persist_mqtt

Tasmota berry module analogous to persist, but stores the data to the MQTT server. If the server lives outside LAN, the connection must be secured with TLS. The variables are stored in cleartext, keep this in mind.

NOTE : We import the module as "pt" to make the examples easier to write and read.

## Installation
Put the persist_mqtt.be file at the top level of the ESP32xx filesystem.

## Importing the module
The fisrt time the module is loaded write in **Berry Scripting Console**:
```
import persist_mqtt as pt
pt.zero() # Creates an empty pool of variables
```
**Do not skip the pt.zero() step, the module will not work !**

After this and for interactive use (BerryConsole), the module can be loaded as usual.

**However for use by other scripts special attention is needed.**
**WARNING ! This one is a little tricky. In 'autoexec.be' add theese lines**

```
import persist_mqtt as pt
pt.exec(/-> load('autoexec_ready.be'))
```

The exec() function only loads 'autoexec_ready.be' when the MQTT server sends the stored variables (Usually < 1 sec).
Any script or code loaded from 'autoexec_ready.be' can use the 'pt' object freely. Write for example
```
print( pt.ready() ) # will print true
```


If we try to load('autoexec_ready.be') outside of exec() the variables will not be there and the script will malfunction.

**Note also that we cannot loop around pt.ready() to check if the variables are ready. Berry is single threaded and code like "while !pt.ready() end" will not allow the pt module to actually get ready(to receive MQTT messages) and will deadlock and freeze the whole ESP32 tasmota system.**

## Usage

```
pt.counter = 1
pt.counter += 1
pt.tones = [600, 700, 800]
# pt.save() generally in not needed unless you disable autosaves
print(pt.counter)
pt.find('counter2', 10) # return 10 is var does not exist
pt.remove('counter2') # does nothing if count2 is not defined
pt.counter2 = nil # Exactly the same as above
```

## Allowed data types
Only values that can be serialized with json can be saved. Fortunatelly this includes most useful cases.
- Simple data types like integers, floats, strings.
- tables ie [1, 2, "test"] , [1, 2.2, [3, "4"]]
- maps with string keys ie {'1':100, '2':[200,'201']} but NOT {1:100, 2:200}
- The bytes data object cannot be saved, it is converted to a string
- About 1000 bytes of json data can be saved. This is OK for the intented purpose, which is to store a limited set of frequently changed values such as counters. For bigger storage needs and data that are not frequently change you can use the persist module.

It is harder(more cpu cycles) for the module to detect changes inside tables and maps, most probably however you wont notice anything.

## Saving the variables
Contarary to buildin persist, the variables autosave in persist_mqtt.
Given that the an MQTT server does not suffer from wear like Flash, any change will be send to the MQTT server in a few ms timeframe. If you prefer the behaviour of persist you can
use pt.savedelay(-1)
Even with autosaves disabled a planned restart (web interface or a "restart 1" command) will trigger a save. Of course a power outage or a crash can lead to data loss, so most of the time you probably prefer to have autosaves enabled. Here is a summary of differences

| persist       |      persist_mqtt |
| --------------|-------------------|
| no autosaves  | yes but can be disabled with save_delay(-1) |
| save() cannot see changes inside tables   | save() detects changes inside tables and maps |
|can be used immediately after import   |   Needs some procedure see #inporting |
| very fast     |      limited by the network latency and the fact that try harder to detect changes |
| flash wear    |      unlimited writes (only limit is the network usage) |
| variables can be seen by accessing the filesystem  |   can be viwed in real time with an mqtt client |

### Methods not present, or working differently than buildin persist

- pt.savedelay(timeSec=real) Schedules a save(to MQTT) at most timeSec seconds in the future. It saves the values IF there are changes to be pushed. Note that persist_mqtt will detect data changes even deep inside tables or maps. Any value <0 will disable auto-saves. The default is 0 and immediatelly triggers a mqtt push. If we have lots of updates and we want to reduce the number of pushes to the server we can to a
pt.savedelay(10) for example.

- pt.selfupdate() fetches an updated (if it exists) persist_mqtt module from the github page. For interactive use only.

- pt.zero() is clearing all the variables like the persist module but if the module is ready() (connected to the mqtt server), it needs a zero(true) for safety. Never put this function in a script. This function is mainly useful when we install persist_mqtt to a tasmota system, and we have to init the variables.

- pt.dirty() Makes the next save to send the data to MQTT even if the server is updated. The difference with persist(tasmota 14.3) is that persist_mqtt detects changes even deep in tables etc. So this function is almost never needed in persist_mqtt.

## Advantages
Note that If the project needs mqtt to work, the use of persist_mqtt does not add an additional point of failure.

- The data can be changed frequently, without limits. On the contrary the persist module uses flash with ~10000 reliable writes. If writing is spread across the flash, the limit may be way bigger (I don't know if tasmota FlashFS and persist are doing this). In any case, using an external storage solves the problem altogether.
- We can inspect the variables with an mqtt client, by listening the stat/+/PersistMQTT making the module a good debugging tool.
- We can move the project to another ESP32 module(using the same topic for the new module) and the variables we stored will be there. In this case the initial .zero() is not needed.
- The autosave feature can simplify the code and it is less error prone.
- The server checks if the request is valid/complete so it is very difficult for the database to be corrupted. Flash storage generally can be corrupted on crashes.
- Works even with Tasmota "savedata = OFF" feature.

## Disadvantages
- The module cannot be used immediatelly, complicating the import as we've seen above. If you follow the pattern with 'autoexec_ready.be' however, you are OK. 
- limited space for variables (~1000 bytes in json format)
- The speed of save() is slow. However mqtt seems to be performed asynchronously, so the save() actually returns fast, but the data needs some time (imposed by network latency) to reach the server.
- **Anyone who has access to the server, can view and change the variables ! BE WARNED ! DO NOT USE IT FOR CONFIDENTIAL DATA**
- if the project does not need an MQTT server or not even network connectivity, the use of this module adds complexity and an unnececary point of failure.

## Temporarily use persist_mqtt instead of persist for development

You may want this to reduce flash wear, or to be able to view the variables in real time.

'autoexec_ready.be' See "Importing the module" above.
```
load('mycode.be')
```

'mycode.be'
```
import persist_mqtt as persist
persist.savedelay(-1) # To simulate somewhat the persist behaviour
# import persist

persist.var1 = 123
persist.var2 = [1,2,3]
persist.var2[1] += 1
persist.dirty() # needed by stock persist for "persist.var2[1] += 1"
persist.save() # needed as persist does not have autosaves
```
## Multiple tasmota modules loading persist_mqtt on the same mqtt server
Make sure the modules have different topic. Check/change this with the "topic" tasmota console command, or from the Web GUI.

## You cannot share variables between tasmota modules
The module does not implement any locking mechanism. Neither listens for mqtt messages, after the initialization. So, any attempt to use it for sharing variables will lead to data loss.
