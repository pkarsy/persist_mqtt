#-
WARNING ! No guaranties about losing important data, see MIT LICENCE
WARNING ! Importing the persist_mqtt module is not straightforward.
See README before use
Version 0.8.10
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
    var _debug # Controls some debugging messages. May be removed finally
    var _dirty

    def init()
      self._dirty = false
      self._exec_callback = [] 
      self._debug = false
      self._pool = {}
      mqtt.unsubscribe(PersistMQTT._topic) # in case of reloading
      mqtt.subscribe(
        PersistMQTT._topic,
        /_topic_, _idx_, msg -> self._receive_cb(msg) # we are interested on the retained message only
      )
      # On a planned restart (restart 1 or GUI restart) a pt.save() is performed
      tasmota.remove_rule(PersistMQTT._save_rule, PersistMQTT._unique_id) # to disconnect older module (devel)
      tasmota.add_rule(PersistMQTT._save_rule, /->self.save(), PersistMQTT._unique_id)
    end

    ### functions that are somewhat equivalent to persist functions ###

    def zero(force) # The persist buildin does not use the true/false argument
      if self.ready() && force!=true
        print('Mqtt is already OK. To force clearing the variables, do a .zero(true)')
        return
      end
      self._pool = {}
      mqtt.publish(PersistMQTT._topic, json.dump(self._pool) , true)
    end

    def member(myvar) # Implements of using pt.myvar
      if self._debug print('member', myvar) end
      if ! self.ready() print(PersistMQTT._errmsg) return end
      return self._pool.find(myvar)
    end

    def setmember(myvar, value) # Implements "pt.myvar = myvalue"
      if self._debug print('setmember', myvar, value) end
      if ! self.ready() print(PersistMQTT._errmsg) return end
      if value == nil
        self.remove(myvar)
        return
      end
      self._pool[myvar]=value
      self._dirty = true
    end

    def remove(myvar)
      if ! self.ready() print(PersistMQTT._errmsg) return end
      var value = self.find(myvar)
      if value == nil return end
      self._pool.remove(myvar)
      self._dirty = true
    end

    def has(myvar)
      if ! self.ready() print(PersistMQTT._errmsg) return end
      return self._pool.has(myvar)
    end

    def dirty() # The next save() will actually send mqtt data
      if ! self.ready() print(PersistMQTT._errmsg) return end
      self._dirty = true
    end

    def find(k, fbval)
      return self._pool.find(k, fbval)
    end

    def save()
      if self._debug print('pt.save()') end
      if !self.ready() print(PersistMQTT._errmsg) return end
      if !self._dirty return end
      mqtt.publish(PersistMQTT._topic, json.dump(self._pool), true)
      self._dirty = false
    end

    ### functions that are not present in persist buildin module ###

    def _receive_cb(msg) # Get the retained msg from the mqtt server
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
      # nil informs the exec() function that no callback is pending
      self._exec_callback = nil
    end

    def exec(cb) # calls the "cb" function/closure when the variables are feched from the server
      if type(cb) != 'function'
        print('Needs a callback function, got', type(cb) )
        return
      end
      if self._exec_callback == nil
        # executes the function in the next tick
        if self._debug print('exec() immediatelly') end
        tasmota.set_timer(0,cb)
      else
        # postpone the execution when the variables are feched from the broker
        if self._debug print('exec() when ready') end
        self._exec_callback.push(cb)
      end
    end

    def ready() # true when vars are feched. You cannot use it in a waiting loop, see the README
      return self._exec_callback == nil
    end

    def selfupdate()
      self.save()
      var fn = '/persist_mqtt.be'
      var fd=open(fn)
      var lbytes = fd.readbytes()
      fd.close() fd = nil
      if size(lbytes) < 2000
        print('Cannot read the local script')
        return
      end
      var cl = webclient()
      cl.begin('https://raw.githubusercontent.com/pkarsy/persist_mqtt/refs/heads/main' + fn)
      cl.GET()
      var rbytes = cl.get_bytes()
      cl.close() cl = nil
      if size(rbytes) < 2000
        print('Cannot fetch the remote script')
        return
      end
      if rbytes == lbytes
        print('The code is up to date')
        return
      end
      lbytes = nil
      fd = open(fn, 'w')
      fd.write(rbytes)
      fd.close()
      print('Got update from github')
    end

    def deinit() # for debugging
      print( '' .. self .. '.deinit()' )
    end

  end # class mqttvar

  return PersistMQTT()
end

return pt_module
