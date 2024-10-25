#-
WARNING ! No guaranties about losing important data, see MIT LICENCE
WARNING ! To use the persist_mqtt module use something like

import persist_mqtt as pt
pt.exec( /-> load('autoexec_ready.be') )

See README for explanation
Version 0.8.8
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
    var _mqttout # The last outqoing msg, so we can know if the mqtt server needs an update
    var _module_ready # true when the server sent us the persistent data (as a retained message)
    static _unique_id = 0xbeef # a unique value. It is used to be able to remove a timer we've created
    var _exec_callback # will be called when we get the retained message
    static _save_rule = 'System#Save' # rule to save the data on planned restarts
    static _errmsg = 'Not ready. The module did not get the variables from the server' # To avoid repeating the same err message across the code
    var _save_delay # Controls autosaves see README
    var _save_is_pending # Used by _schedule_save() to not trigger another save() if one is pending
    var _debug # Controls some debugging messages. May be removed finally

    def init()
      self._debug = false
      self._save_delay = 0 # ms
      self._save_is_pending = false
      self._pool = {}
      mqtt.unsubscribe(PersistMQTT._topic) # in case of reloading
      tasmota.remove_timer(PersistMQTT._unique_id) # in case of reloading
      self._module_ready = false # it will become ready when we fetch the variables
      mqtt.subscribe(
        PersistMQTT._topic,
        /_topic_, _idx_, msg -> self._mqtt_callback(msg) # we are interest on the retained message only
      )
      # On a planned restart (restart 1 or GUI restart) a pt.save() is performed
      tasmota.remove_rule(PersistMQTT._save_rule, PersistMQTT._unique_id)
      tasmota.add_rule(PersistMQTT._save_rule, /->self.save(), PersistMQTT._unique_id)
    end

    ### functions that are somewhat equivalent to persist functions ###

    def zero(force) # The persist buildin does not use the true/false argument
      if self._module_ready && force!=true
        print('Mqtt is already OK. To force clearing the variables, do a .zero(true)')
        return
      end
      self._pool = {}
      self._mqttout = json.dump(self._pool)
      mqtt.publish(PersistMQTT._topic, self._mqttout , true)
    end

    def member(myvar) # Implements of using pt.myvar
      if ! self._module_ready print(PersistMQTT._errmsg) return end
      var value = self._pool.find(myvar)
      # For int real and string there is no need to save, they are immutable
      if type(value)!='instance' return value end
      self._schedule_save()
      return value
    end

    def setmember(myvar, value) # Implements "pt.myvar = myvalue"
      if ! self._module_ready print(PersistMQTT._errmsg) return end
      if value == nil
        self._pool.remove(myvar)
      else
        self._pool[myvar]=value
      end
      self._schedule_save()
    end

    def _schedule_save()
      if self._save_delay < 0 return end
      if self._save_is_pending return end
      tasmota.remove_timer(PersistMQTT._unique_id) # Not needed ?
      tasmota.set_timer(
        int(self._save_delay),
        /->self.save(),
        PersistMQTT._unique_id
      )
      self._save_is_pending = true
    end

    def remove(myvar)
      self._pool.remove(myvar)
    end

    def has(myvar, fallback_val)
      if ! self._module_ready print(PersistMQTT._errmsg) return end
      return self._pool.has(myvar, fallback_val)
    end

    def dirty() # The next save() will actually send mqtt data
      self._mqttout = nil
    end

    def find(k, fbval)
      return self._pool.find(k, fbval)
    end

    def save()
      if self._debug print('pt.save()') end
      if ! self._module_ready print(PersistMQTT._errmsg) return end
      tasmota.remove_timer(PersistMQTT._unique_id)
      self._save_is_pending = false
      var poolser = json.dump(self._pool)
      if poolser == self._mqttout return end
      self._mqttout = poolser
      mqtt.publish(PersistMQTT._topic, self._mqttout, true)
    end

    ### functions that are not present in persist buildin module ###

    def _mqtt_callback(msg) # Get the retained msg from the mqtt server
      var jsonmap = json.load(msg)
      if classname(jsonmap)=='map'
        self._pool = jsonmap
      else
        print('Got invalid json from broker')
        return
      end
      mqtt.unsubscribe(PersistMQTT._topic) # we are interested only for the retained message
      self._module_ready = true
      self._mqttout = msg # no need to send this message to the server, there is already there
      if type(self._exec_callback) == 'function'
        self._exec_callback()
      end
      # nil informs the exec() function that no callback is pending
      self._exec_callback = nil
    end

    def exec(cb) # calls the "cb" function/closure when the variables are feched from the server
      if type(cb) != 'function'
        print('Needs a callback function, got', type(cb) )
        return
      end
      if self._exec_callback != nil
        print('A callback is pending')
        return
      end
      if self._module_ready
        # executes the function immediatelly
        if self._debug print('exec() immediatelly') end
        tasmota.set_timer(0,cb)
        #return true
      else
        # postpone the execution when the variables are feched from the broker
        if self._debug print('exec() when ready') end
        self._exec_callback = cb
        #return false
      end
    end

    def ready() # true when vars are feched. You cannot use it in a waiting loop, see the README
      return self._module_ready
    end

    def savedelay(sec)
      if type(sec)!='int' && type(sec)!='real' return self._save_delay end
      self.save()
      if sec<0 self._save_delay = -1 tasmota.remove_timer(PersistMQTT._unique_id) return end
      self._save_delay = int(1000*sec)
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
