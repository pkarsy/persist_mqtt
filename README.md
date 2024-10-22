# persist_mqtt

NOTE : We import the module as "pt" to make the examples easier to write and read

Tasmota berry module analogous to persist, but stores the data to the MQTT server defined in tasmota settings. If the server lives outside LAN, the connection must be secured with TLS. The variables are stored in cleartext, keep this in mind.

## Installation
Put the persist_mqtt.be file at the top level of the ESP32xx filesystem

## Importing the module
The fisrt time the module is loaded write in **Berry Scripting Console**:
```
import persist_mqtt as pt
pt.zero() # Creates an empty pool of variables
```
**Do not skip the pt.zero() step, the module will not work !**

After this and for interactive use (BerryConsole), the module can be loaded as usual.

**However for use by other scripts special attention is needed.**

**WARNING ! This one is a little tricky. In 'autoexec.be' add
theese lines**

```
import persist_mqtt as pt
pt.exec(/-> load('autoexec_ready.be'))
# print( pt.ready() ) # will print false, there wasn't time to fetch the vars.
```

The exec() function only loads 'autoexec_ready.be' when the MQTT server sends the stored variables (Usually < 1 sec).
Any script or code loaded from 'autoexec_ready.be' can use the 'pt' object freely.
Indeed the line

```
print( pt.ready() )
```
will print true.

If we try to load('autoexec_ready.be') outside of exec() the variables will not be there and the script will malfunction.

**Note also that we cannot loop around pt.ready() to check if the variables are ready. Berry is single threaded and code like "while !pt.ready() end" will not allow the pt module to actually get ready(to receive MQTT messages) and will deadlock and freeze the whole ESP32 tasmota system.**

## Usage

```
pt.counter = 1
pt.counter += 1
pt.tones = [600,700,800]
pt.save()
print(pt.counter)
pt.has('counter',10) # return 10 is var does not exist
pt.remove('count2') # does nothing if count2 is not defined
pt.save_every(60) # seconds
```

## Allowed data types
Only values that can be serialized with json can be saved. Fortunatelly this includes all useful cases.
- Simple data types like integers, floats, strings
- tables ie [1,2,"test"] , [1, 2.2 , [3,"4"]]
- maps with string keys ie {'1':100, '2':[200,'201']} but NOT {1:100, 2:200}
- About 1000 bytes of json data can be saved. This is OK for the intented purpose which is to store a limited set of frequently changed values such as counters. For bigger storage needs and data that are not frequently change you can use the persist module

## Saving the variables
As with persist, the values are not saved automatically. Use pt.save() whenever is needed.

if there is a planned restart (web interface or a "restart 1" command), a save will be performed automatically, but NOT if there is a power outage or a crash. See save_every() for a mitigation to the problem. 

### Methods not present, or working differently than buildin persist

- pt.save_every(sec>=5) saves the values IF there are changes to be pushed. Note that persist_mqtt will detect data changes even deep inside tables or maps. Any value <5sec will disable auto-saves. Not present in persist.

- pt.selfupdate() fetches an updated (if it exists) persist_mqtt module from the github page. For interactive use only.

- pt.zero() is clearing all the variables like the persist module but if the module is ready(), it needs a zero(true) for safety. Never put this function in a script. This function is mainly useful when we install persist_mqtt to a tasmota system, and we have to init the variables.

- pt.dirty() Makes the next save to send the data to MQTT even if the server is updated. The difference with persist(tasmota 14.3) is that persist_mqtt detects changes even deep in tables etc. So this function is almost never needed in persist_mqtt.

## Advantages
Note that If the project needs mqtt to work, the use of persist_mqtt does not add an additional point of failure.

- The data can be changed frequently, without limits. On the contrary the persist module uses flash with ~10000 reliable writes. If writing is spread across the flash, the limit may be way bigger (I don't know if tasmota FlashFS and persist are doing this). In any case, using an external storage solves the problem altogether.
- We can inspect the variables with an mqtt client, by listening the stat/+/PersistMQTT making the module a good debugging tool.
- We can move the project to another ESP32 module(using the same topic for the new module) and the variables we stored will be there. In this case the initial .zero() is not needed.
- The save_every(seconds) feature can simplify the code, if we accept the small possibility to miss a very resent variable change (in the event of a unplanned reset/power off).
- The server checks if the request is valid/complete so it is very difficult for the database to be corrupted. Flash storage generally can be corrupted on crashes.
- Works even with Tasmota "savedata = OFF" command

## Disadvantages
- The module cannot be used immediatelly, complicating the import as we've seen above. If you follow the pattern with 'autoexec_ready.be' however, you are OK. 
- limited space for variables (~1000 bytes in json format)
- The speed of save() is slow. However mqtt is seems to be performed asynchronously, so the save() actually returns fast, but the data needs some time (imposed by network latency) to reach the server. The other operations pt.var1=val1 etc do not have a speed penaly
- **Anyone who has access to the server, can view and change the variables ! BE WARNED ! DO NOT USE IT FOR CONFIDENTIAL DATA**
- if the project does not need an MQTT server or not even network connectivity, the use of this module adds complexity and an unnececary point of failure.

## Temporarily use persist_mqtt instead of persist for development
You may want this to reduce flash wear, to be able to view the variables in real time, or to be able to switch development modules without loosing your data.

'autoexec_ready.be' See "Importing the module" above
```
load('mycode.be')
```

'mycode.be'
```
import persist_mqtt as persist
# import persist

persist.var1 = 123
persist.dirty()
persist.save()
```
## Multiple tasmota modules loading persist_mqtt on the same mqtt server
Make sure the modules have different topic. Check/change this with the "topic" tasmota console command, or from the Web GUI

## You cannot share variables between tasmota modules
The module does not implement any locking mechanism, neither saves the data in real time. So any attempt to use it for sharing variables will lead to data loss.
