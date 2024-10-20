# persist_mqtt

NOTE : We import the module as "pt" to make the examples easier to write and read

Tasmota berry module analogous to persist, but stores the data to the MQTT server defined in tasmota settings. If the server lives outside LAN, the connection must be secured with TLS

## Installation
Put the persist_mqtt.be file at the top level of the ESP32xx filesystem

## Importing the module
The fisrt time the module is loaded write in BerryScriptingConsole:
```
import persist_mqtt as pt
#
# Creates an empty pool of variables in the MQTT server
# Do not skip this .zero() step, the module will not work
#
pt.zero()
```
After ths and for interactive usage (BerryConsole), the module can be loaded as usual. **However for use by other scripts special attention is needed.**

**WARNING ! This one is a little tricky. In 'autoexec.be' put
theese lines**

```
import persist_mqtt as pt
pt.exec(/-> load('mycode.be'))
```

The exec() function only loads 'mycode.be' when the MQTT server sends the stored variables (Usually < 1 sec).

If we load('mycode.be') outside of exec() the variables will not be there and the script will mullfunction.

**Note also that we cannot loop around pt.ready() to check if the variables are ready. Berry is single threaded
and code like "while !pt.ready() end" will not allow the pt module to actually get ready(to receive MQTT messages) and will
deadlock and freeze the whole ESP32 tasmota system.**

## Usage
Works like the persist buildin module

```
pt.counter = 1
pt.counter += 1
pt.tones = [600,700,800]
pt.save()
print(pt.counter)
pt.has('counter',10) # return 10 is var does not exist
pt.remove('count2') # does nothing if count2 is not defined
```

## Allowed data types
Only values that can be serialized with json can be saved. Fortunatelly this includes all practical cases.
- Simple data types like integers, floats, strings
- tables ie [1,2,"test"] , [1, 2.2 , [3,"4"]]
- maps with string keys ie {'1':100, '2':[200,'201']} but NOT {1:100, 2:200}
- About 1000 bytes of json data can be saved. This is OK for the intented purpose which is to store a limited set of frequently changed values such as counters. For bigger staorage needs and data that are not frequently change you can use the persist module

## Saving the variables
As with persist the values are not saved immedatelly. Use pt.save() whenever is needed.

if there is a restart from the web interface or a restart 1 console/mqtt command, at save() will be performed automatically, but NOT if there is a power outage a crash of the BerryVM or anything similar. See also save_every() for an alternative way to save the data. 

### Methods not present, or working differently than buildin persist

- pt.save_every(sec) saves the values IF there are changes to the stored data. Note that persist_mqtt will detect data changes even deep inside tables or maps. Not present in persist

- pt.selfupdate() fetches an updated (if it exists) persist_mqtt module from the github page. Not preset in persist

- pt.zero() is clearing all the variables like the persist module but if the module is ready(), it needs a zero(true) for safety.

- pt.dirty() Makes the next save to send the data to MQTT even if the server is updated. The difference with persist(tasmota 14.3) is that persist_mqtt detects changes even deep in tables etc. So this function is not as useful as with persist.

## Use cases
Here are some advantages over persist:

- If the project needs mqtt to work, the use of persist_mqtt does not add complexity, neither an additional point of failure.
- The data can be changed frequently withut limits. On the contrary the persist module imposes a some problems to the developer with ~10000 reliable writes.
- We can inspect the variables with an mqtt client by listening the stat/tsamota_topic/PersistMQTT making the module a good debugging tool.
- We can move the project to another esp32 module(using the sane topic) and the variables we stored will be there.
- The save_every(seconds) feature can simplify the code,if we can tolerate to miss a very resent variable (in the event of a unplanned reset/power off). Minimum is 5 sec (at this time) 
- Works even with Tasmota "savedata = OFF" command

On the other hand there are some disadvantages also:

- limited space for variables (~1000 bytes in json format)
- The module cannot be used immediatelly, complicating the import as we've seen above.
- The speed of save() is slow. The good news is that mqtt is performed asynchronously (I believe) so the save() actually returns fast but the data needs some time (in the range of 0.1-0.5 sec) to reach the server. The other operations pt.var1=val1 etc do not have a speed penaly
- Whenever has access to the server can view and change the variables ! BE WARNED !
- if the project does not need an MQTT server or even networkconnectivity, the use this module adds an unnececary point of failure. In this case can only be used on development to be able to visually see the variables on MQTT server.

## Temporarily using persist_mqtt instead of persist for development
You may want this for 2 reasons. To reduce flash wear and to be able to view the variables in real time.

'autoexec.be'
```
import persist_mqtt as pt
pt.exec( /-> load('mycode.be'))
```

'mycode.be'
```
import persist_mqtt as persist
# after the development phase
# import persist
# The code does not need any changes from now on
# The "persist" object is in fact persist_mqtt

persist.var1 = 123
...
persist.dirty()
persist.save()
```
