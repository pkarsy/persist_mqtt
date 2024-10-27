#-
WARNING ! No guaranties about losing important data, see MIT LICENCE
WARNING ! Importing the persist_mqtt module is not as straightforward as persist.
See README before use
Version 0.9.2
-#

var pt_module = module("persist_mqtt")

# the module has a single member init()
# and delegates everything to the inner class
pt_module.init = def (m)
  
  import strict
  import mqtt
  import json

  class PersistMQTT

    var _pool # Stores all persistent variableName:value pairs
    static _topic = 'stat/' + tasmota.cmd('Topic', true)['Topic'] + '/PersistMQTT' # persistent data location
    static _unique_id = 0xbeef # a unique value. It is used to be able to remove a timer we've created
    var _exec_callback # will be used when we get the retained message
    static _save_rule = 'System#Save' # rule to save the data on planned restarts
    static _errmsg = 'Not ready. The module did not get the variables from the server' # To avoid repeating the same err message across the code
    var _dirty
    var _ready

    def init()
      self._ready = false
      self._exec_callback = [] 
      mqtt.unsubscribe(PersistMQTT._topic) # devel
      mqtt.subscribe(
        PersistMQTT._topic,
        /_topic_, _idx_, msg -> self._receive_cb(msg) # we are interested on the retained message only
      )
      # On a planned restart (restart 1 or GUI restart) a pt.save() is performed
      tasmota.remove_rule(PersistMQTT._save_rule, PersistMQTT._unique_id) # devel
      tasmota.add_rule(PersistMQTT._save_rule, /->self.save(), PersistMQTT._unique_id)
    end

    ### functions that work as the stock persist ###

    def zero()
      if !self._ready print(PersistMQTT._errmsg) return end
      self._pool = {}
      self._dirty = true
    end

    def member(myvar) # Implements of using "pt.myvar"
      return self._pool.find(myvar)
    end

    def setmember(myvar, myvalue) # Implements "pt.myvar = myvalue"
      if ! self._ready print(PersistMQTT._errmsg) return end
      self._pool[myvar]=myvalue
      self._dirty = true
    end

    def remove(myvar)
      self._pool.remove(myvar)
      self._dirty = true
    end

    def has(myvar)
      return self._pool.has(myvar)
    end

    def dirty() # The next save() will actually send mqtt data
      self._dirty = true
    end

    def find(myvar, fallback_val)
      return self._pool.find(myvar, fallback_val)
    end

    def save()
      if !self._ready print(PersistMQTT._errmsg) return end
      if !self._dirty return end
      mqtt.publish(PersistMQTT._topic, json.dump(self._pool), true)
      self._dirty = false
    end

    ### functions that are not exist in persist buildin module ###

    def values() # for debugging
      return json.dump(self._pool)
    end

    def initvars()
      if self._ready
        print('The vars are already loaded')
        return
      end
      mqtt.publish(PersistMQTT._topic, "{}", true)
      print('Init with empty pool')
    end

    def _receive_cb(msg) # For internal use. Get the retained msg from the mqtt server
      var jsonmap = json.load(msg)
      if classname(jsonmap)=='map'
        self._pool = jsonmap
      else
        print('Got invalid json from broker')
        return
      end
      mqtt.unsubscribe(PersistMQTT._topic) # we are interested only for the retained message
      for f:self._exec_callback
        tasmota.set_timer(0,f)
      end
      self._exec_callback = []
      self._ready = true
    end

    def exec(cb) # calls the "cb" function/closure when the variables are feched from the server
      if type(cb) != 'function'
        print('Needs a callback function, got', type(cb) )
        return
      end
      if self._ready
        # executes the function in the next tick
        tasmota.set_timer(0,cb)
      else
        # postpone the execution for the variables to become ready
        self._exec_callback.push(cb)
      end
    end

    def ready() # true when vars are feched. You cannot use it in a waiting loop, see the README
      return self._ready
    end

    def selfupdate()
      self.save()
      var fn = '/pt.be'
      var fd=open(fn)
      var local_script = fd.read() # string
      fd.close() fd = nil
      if size(local_script) < 2000 # a simple check
        print('Cannot read the local script')
        return
      end
      var cl = webclient()
      cl.begin('https://raw.githubusercontent.com/pkarsy/persist_mqtt/refs/heads/main' + fn)
      cl.GET()
      var remote_script = cl.get_string()
      cl.close() cl = nil
      if size(remote_script) < 2000
        print('Cannot get the remote script')
        return
      end
      if remote_script == local_script
        print('The code is up to date')
        return
      end
      local_script = nil
      fd = open(fn, 'w')
      fd.write(remote_script)
      fd.close()
      print('Got update from github. Reset the module, to use the new code.')
    end

    def deinit() # for debugging
      print( '' .. self .. '.deinit()' )
    end

  end # class PersistMQTT

  return PersistMQTT()
end

return pt_module
