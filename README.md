# persist_mqtt

Tasmota berry module analogous to persist, but stores the data to the MQTT server. One can switch from persist to persist_mqtt (or the opposite) at any time when developing, only by changing the import method. Tested with Tasmota 14.3

If the server lives outside LAN, the connection must be secured with TLS. The variables are stored in cleartext, keep this in mind.


## Quick installation
copy and paste the following code to the Berry Console
```berry
do
  var fn = 'pt.be'
  var cl = webclient()
  var url = 'https://raw.githubusercontent.com/pkarsy/persist_mqtt/refs/heads/main/'+fn
  cl.begin(url)
  var r = cl.GET()
  if r != 200 print('Error getting',fn) end
  var s = cl.get_string()
  cl.close()
  var f = open('/'+fn, 'w')
  f.write(s)
  f.close()
  print('Installed', fn)
end
```

## Manual Installation
Put the "pt.be" file at the top level of the ESP32xx filesystem.

## Initializing the module for the first time
Write in **Berry Scripting Console**:
```berry
> # Warning interactive console
> import pt
> pt.initvars() # Creates an empty pool of variables.
```
**Do not skip the pt.initvars() step, the module will not work ! This step must to be done only once. Do not put a pt.initvars() in a script**

After this and for interactive use (Berry Scripting Console), the module can be loaded as usual.

## Import the module in scripts
For use by other scrips or "autoxec.be", **special attention is needed**. When the module is first imported (after boot), it needs some time to get (asynchronously) the variables from the server. Any code trying to use the module in this time, will find it in an unusable state (all variables will retutn nil and no assignment is possible).

**Note that we cannot wait for pt.ready() to become true.** Berry is single threaded, and code like "while !pt.ready() end" will not allow the pt module to actually get ready (to receive MQTT messages) and will deadlock and freeze the whole ESP32 tasmota system.

## Importing the module, method 1

In 'autoexec.be' add theese lines

```berry
import  pt
pt.exec(/-> load('myscript1.be'))  # will be executed only after the variables are ready
pt.exec( /-> load('myscript2.be')) # both scripts can use the "pt" object freely
```

## Method 2
Works without relying on "autoexec.be" exec(), and without even including "pt" in the global namespace. If the script needs to be started from "autoexec.be", load the script as usual with load('mycode.be'). Or just paste the code inside autoexec.be

```berry
do # optional, hides BootCount() from the global namespace
  def BootCount()
    import pt
    if !pt.ready() pt.exec(BootCount) return end
    # your code goes here. May be executed asynchronously
    if pt.BootCount == nil
      pt.BootCount = 1
    else
      pt.BootCount += 1
    end
    pt.save() # sends the updated var to the server, inspect the MQTT messages
    print('BootCount =', pt.BootCount)
  end

  BootCount() 
end

```
The line containing "if !pt.ready()..." does all the magic, basically the function is reexecuted when the variables are ready.

## Usage (Identical with persist)
```berry
pt.counter = 1
pt.save() # works ok
...
pt.counter += 1
pt.save() # works ok
...
pt.tones = [600, 700, 800]
pt.save() # works ok
...
pt.tones = [600, 700, 800, 800]
pt.save() # works ok. Any assignement "pt.myvar = myvalue" will make the next save to work.
...
pt.tones[2]=1600 # or pt.tones[2] *= 2 # pt cannot detect this (neither persist)
pr.dirty()
pt.save() # without .dirty() will not save the variable
...
pt.has('counter') # -> true/false
pt.remove('counter') # does nothing if var "pt.counter" is not defined
#
# pt.has() can distinguish between a non existent variable and a nil one.
#
pt.newvar == nil # returns true if 'newvar' is not defined
pt.has('newvar') # -> false
pt.newvar = nil
pt.has('newvar') # -> true this time
#
pt.find('newvar2') # -> nil
pt.find('newvar2', 10) # returns 10 if var does not exist
```

## Allowed data types
Only values that can be serialized with json can be saved. Fortunatelly this includes most useful cases.
- Simple data types like integers, reals, strings.
- tables ie [1, 2, "test"] , [1, 2.2, [3, "4"]]
- maps with string keys ie {'1':100, '2':[200,'201']} but not {1:100, 2:200}
- The bytes data object cannot be saved, it is converted to a string
- About 1000 bytes of json data can be saved. This is OK for the intented purpose, which is to store a limited set of frequently changed values such as counters. For bigger storage needs, or data that are not frequently changing, you can use the persist module.

## Saving the variables
pt.save() like persist.save() is the responsibility of the developer. On a planned restart (web interface or a "restart 1" command) a pt.save() will be performed automatically (persist also is doing the same). Of course a power outage or a crash will lead to data loss. Here is a summary of differences between persist and persist_mqtt

| persist       |      persist_mqtt(pt) |
| --------------|-------------------|
|no network is needed|needs network and MQTT server|
|can be used immediately after import   |   Needs some procedure see above |
| very fast     |      limited by the network latency |
| flash wear    |      unlimited writes (only limit is the network usage) |
| variables can only be seen by accessing the filesystem  |   can be viewed in real time with an mqtt client |

### Methods not present in buildin persist

- **pt.ready()** and **pt.exec(func)**. Used when importing the module, as we've seen.

- **pt.values()** For debugging purposes, return the full database of vars as a json string.

- **pt.selfupdate()** fetches an updated (if it exists) "pt.be" module from the github page. For interactive use only.

- **pt.initvars()** Used when we install persist_mqtt to a new tasmota system(with a new unique "topic"), and we have to init the variables. For interactive use only.

## Pros
- The data can be changed frequently, without limits, which is a consideration with internal flash.
- We can inspect the variables with an MQTT client, making the module a good debugging tool.
- The server checks if the request is valid/complete so it is very difficult for the database to be corrupted.

## Cons
- The module cannot be used immediatelly, complicating the import as we've seen above.
- limited space for variables (~1000 bytes in json format)
- The speed of save() is slow due to netwotk latency. However mqtt seems to be performed asynchronously, so the save() actually returns fast.
- **Anyone who has access to the server, can view and change the variables ! Even worse if the connection is not secured with SSL/TLS. BE WARNED ! DO NOT USE IT FOR CONFIDENTIAL DATA**
- Cannot be used (or adds complexity) if the tasmota system does not use an MQTT server or has no network at all.

## How to temporarily use persist_mqtt(pt) instead of persist for development

You may want this to reduce flash wear when writing a new berry program, or to be able to view the variables in real time.

```berry
def myfunc()
  # any time you can switch back to persist
  # import persist
  import pt as persist
  if !pt.ready() pt.exec(myfunc) return end
  # no need to change the code
  persist.var1 += 1
  persist.save()
end
```
## Multiple tasmota modules loading persist_mqtt on the same mqtt server
Make sure the modules have different topic. Check/change this with the "topic" tasmota console command, or from the Web GUI.

## You cannot share variables between tasmota systems
The module does not implement any locking mechanism. Neither listens for mqtt messages, after the initialization. So, any attempt to use it for sharing variables will lead to data loss.
