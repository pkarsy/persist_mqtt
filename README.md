# persist_mqtt

Tasmota berry module analogous to persist, but stores the data to the MQTT server. If the server lives outside LAN, the connection must be secured with TLS. The variables are stored in cleartext, keep this in mind.

## Installation
Put the "pt.be" file at the top level of the ESP32xx filesystem.

## Importing the module for the first time
Write in **Berry Scripting Console**:
```
> import  pt
> pt.zero() # Creates an empty pool of variables.
```
**Do not skip the pt.zero() step, the module will not work ! This step must to be done only once. Do not put a pt.zero() in a script**

After this and for interactive use (Berry Scripting Console), the module can be loaded as usual.

**IMPORTANT !**
For use by automatically loaded code, special attention is needed. When the module is imported it needs some time to fetch(asynchronously) the variables from the server. Any code trying to use the module in this timeframe, will find it in an unusable state (all variables will be nil).

**Note that we cannot just wait pt.ready() to become true.** Berry is single threaded, and code like "while !pt.ready() end" will not allow the pt module to actually get ready(to receive MQTT messages) and will deadlock and freeze the whole ESP32 tasmota system.

## Importing the module, method 1

In 'autoexec.be' add theese lines

```
import  pt
pt.exec(/-> load('myscript1.be'))  # will be executed only after the variables are fetched
pt.exec( /-> load('myscript2.be')) # both scripts can use the "pt" object freely
                                   # The sripts will be executed after autoexec finishes
```

## Method 2 (better)
Works without relying on "autoexec.be" exec() trick, and without even importing pt in the global namespace. If the script needs to be started from "autoexec.be", load the script as usual with load('mycode.be'). Or just paste the code inside autoexec.be

```
do # do-end is optional, does not allow the BootCount() to be visible in the global namespace.
  def BootCount()
    import pt
    if !pt.ready() pt.exec(BootCount) return end
    # your code goes here.
    if pt.BootCount == nil
      pt.BootCount = 1
    else
      pt.BootCount += 1
    end
    print('BootCount =', pt.BootCount)
  end

  BootCount()
end
```
The line containing "if !pt.ready()..." does all the magic, basically the function is reexecuted when the variables are feched.

## Usage
The module tries to behave like the stock persist module for 2 main reasons :
- Knowing the persist usage, you already know how to use this module.
- To be able to use them interchangeably, se the last paragraph.

```
pt.counter = 1
pt.save()
...
...
pt.counter += 1
pt.save() # works ok
...
...
pt.tones = [600, 700, 800]
pt.save() # works ok
...
pt.tones = [600, 700, 800, 800]
pt.save() # works ok. Any assignement "pt.myvar = myvalue" works
...
...
pt.tones[2]=1600 # or pt.tones[2] *= 2
pr.dirty() # cannot detect changes inside the table
pt.save() # without .dirty() will not save the variable
...
pt.has('counter') # -> true/false
pt.remove('counter') # does nothing if var "pt.counter" is not defined
pt.counter == nil # The same as pt.remove('counter')
pt.counter # returns nil is 'counter' is not defined
pt.find('counter') # the same as above
pt.find('counter', 10) # returns 10 is var does not exist
```

## Allowed data types
Only values that can be serialized with json can be saved. Fortunatelly this includes most useful cases.
- Simple data types like integers, floats, strings.
- tables ie [1, 2, "test"] , [1, 2.2, [3, "4"]]
- maps with string keys ie {'1':100, '2':[200,'201']} but not {1:100, 2:200}
- The bytes data object cannot be saved, it is converted to a string
- About 1000 bytes of json data can be saved. This is OK for the intented purpose, which is to store a limited set of frequently changed values such as counters. For bigger storage needs, or data that are not frequently changing, you can use the persist module.

## Saving the variables
pt.save() like persist.save() is the responsibility of the developer. On a planned restart (web interface or a "restart 1" command) a pt.save() will be performed automatically(persist do the same). Of course a power outage or a crash can lead to data loss, Here is a summary of differences between persist and persist_mqtt

| persist       |      persist_mqtt(pt) |
| --------------|-------------------|
|no network is needed|needs network and MQTT server|
|can be used immediately after import   |   Needs some procedure see above |
| very fast     |      limited by the network latency |
| flash wear    |      unlimited writes (only limit is the network usage) |
| variables can be seen by accessing the filesystem  |   can be viwed in real time with an mqtt client |

### Methods not present, or working differently than buildin persist

- pt.selfupdate() fetches an updated (if it exists) persist_mqtt module from the github page. For interactive use only.

- pt.zero() is clearing all the variables like the persist module but if the module is ready() (connected to the mqtt server), it needs a zero(true) for safety. Never put this function in a script. This function is mainly useful when we install persist_mqtt to a tasmota system, and we have to init the variables.

- pt.dirty() Makes the next save to send the data to MQTT even if the server is updated.

## Advantages
Note that If the project needs mqtt to work, the use of persist_mqtt does not add an additional point of failure.

- The data can be changed frequently, without limits, which is a consideration with internal flash.
- We can inspect the variables with an MQTT client, making the module a good debugging tool.
- The server checks if the request is valid/complete so it is very difficult for the database to be corrupted.

## Disadvantages
- The module cannot be used immediatelly, complicating the import as we've seen above.
- limited space for variables (~1000 bytes in json format)
- The speed of save() is slow due to netwotk latency. However mqtt seems to be performed asynchronously, so the save() actually returns fast.
- **Anyone who has access to the server, can view and change the variables ! BE WARNED ! DO NOT USE IT FOR CONFIDENTIAL DATA**
- Cannot be used (or adds complexity) if the tasmota system does not use an MQTT server or no network at all.

## How to temporarily use persist_mqtt instead of persist for development

You may want this to reduce flash wear for your special board, or to be able to view the variables in real time (see above)

```
def myfunc()
  import pt as persist
  if !pt.ready() pt.exec(myfunc) return end
  # import persist

  persist.var1 = 123
  persist.var2 = [1,2,3]
  persist.var2[1] += 1
  persist.dirty() # needed for "persist.var2[1] += 1"
  persist.save()
end
```
## Multiple tasmota modules loading persist_mqtt on the same mqtt server
Make sure the modules have different topic. Check/change this with the "topic" tasmota console command, or from the Web GUI.

## You cannot share variables between tasmota modules
The module does not implement any locking mechanism. Neither listens for mqtt messages, after the initialization. So, any attempt to use it for sharing variables will lead to data loss.
