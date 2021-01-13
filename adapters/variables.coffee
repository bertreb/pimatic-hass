module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = require("lodash")

  class VariablesAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discovery_prefix = discovery_prefix
      @hassDevices = {}

      for _variable in device.config.variables
        env.logger.debug "Adding variable: " + _variable.name
        @hassDevices[_variable.name] = new variableManager(@device, _variable, @client, discovery_prefix, device_prefix)

    publishState: () =>
      for i, variable of @hassDevices
        variable.publishState()

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        publishDiscoveries = []
        for i, variable of @hassDevices
          publishDiscoveries.push variable.publishDiscovery()
          Promise.all(publishDiscoveries)
          .then ()=>
            resolve @id
        )

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        clears =[]
        destroys =[]
        for i, variable of @hassDevices
          clears.push @hassDevices[i].clearDiscovery()
          destroys.push @hassDevices[i].destroy()
        Promise.all(clears)
        .then ()=>
          return Promise.all(destroys)
        .then ()=>
          resolve()
        .catch (err) =>
          env.logger.debug "Error clear and destroy "
      )
            
    clearDiscovery: () =>
      for i, variable of @hassDevices
        @hassDevices[i].clearDiscovery()

    handleMessage: (packet) =>
      for i, variable of @hassDevices
        variable.handleMessage(packet)

    update: (deviceNew) =>
      addHassDevices = []
      removeHassDevices = []

      for _variable,i in deviceNew.config.variables
        if !_.find(@hassDevices, (hassD) => hassD.variable.name == _variable.name )
          addHassDevices.push deviceNew.config.variables[i]
      removeHassDevices = _.differenceWith(@device.config.variables,deviceNew.config.variables, _.isEqual)
      for removeDevice in removeHassDevices
        env.logger.debug "Removing variable " + removeDevice.name
        @hassDevices[removeDevice.name].clearDiscovery()
        .then ()=>
          @hassDevices[removeDevice.name].destroy()
          delete @hassDevices[removeDevice.name]

      @device = deviceNew
      for _variable in addHassDevices
        env.logger.debug "Adding variable" + _variable.name
        @hassDevices[_variable.name] = new variableManager(deviceNew, _variable, @client, @discovery_prefix, device_prefix)
        @hassDevices[_variable.name].publishDiscovery()
        .then((_i) =>
          setTimeout( ()=>
            @hassDevices[_i].publishState()
          , 5000)
        ).catch((err) =>
        )

    setStatus: (online) =>
      for i, _variable of @hassDevices
        @hassDevices[i].setStatus(online)

    destroy: ->
      return new Promise((resolve,reject) =>
        for i,variable of @hassDevices
          @hassDevices[i].destroy()
        resolve()
      )


  class variableManager extends events.EventEmitter

    constructor: (device, variable, client, discovery_prefix, device_prefix) ->  
      @name = device.name
      @id = device.id
      @device = device
      @variable = variable
      @unit = @device.attributes[@variable.name]?.unit ? ""
      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id + "_" + @variable.name
      @hassDeviceFriendlyName = device_prefix + ": " + device.id + "." + @variable.name
      @_getVar = "get" + (@variable.name).charAt(0).toUpperCase() + (@variable.name).slice(1)
      #env.logger.debug "_getVar: " + @_getVar

      @_variableName = @variable.name
      @_handlerName = @variable.name + "Handler"
      @[@_handlerName] = (val) =>
        env.logger.debug "Variable '#{@variable.name}' change: " + val
        @publishState()
      @device.on @_variableName, @[@_handlerName]
      env.logger.debug "Variable constructor " + @name + ", handlerName: " + @_handlerName

    handleMessage: (packet) =>
      #env.logger.debug "handlemessage sensor -> No action" # + JSON.stringify(packet,null,2)
      return

    getDeviceClass: ()=>
      switch @unit
        when "hPa" or "mbar"
          @device_class = "pressure"
        when "kWh" or "Wh" or "mWh"
          @device_class = "energy"
        when "W" or "kW" or "mW"
          @device_class = "power"
        when "lx" or "lm"
          @device_class = "illuminance"
        when "A" or "kA" or "mA"
          @device_class = "current"
        when "V" or "mV" or "kV"
          @device_class = "voltage"
        when "°C" or "°F"
          @device_class = "temperature"
        else
          @device_class = null
      return @device_class

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, (err) =>
          if err
            env.logger.error "Error publishing Discovery Variable  " + err
            reject()
          resolve()
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _configVar = 
          name: @hassDeviceFriendlyName
          unique_id :@hassDeviceId
          state_topic: @discoveryId + '/sensor/' + @hassDeviceId + "/state"
          unit_of_measurement: @unit
          value_template: "{{ value_json.variable}}"
          availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
          payload_available: "online"
          payload_not_available: "offline"
        _deviceClass = @getDeviceClass()
        if _deviceClass?
          _configVar["device_class"] = _deviceClass
        _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_configVar)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_configVar), (err) =>
          if err
            env.logger.error "Error publishing Discovery Variable  " + err
            reject()
          resolve(@variable.name)
        )
      )

    publishState: () =>
      return new Promise((resolve,reject) =>
        try
          @device[@_getVar]()
          .then (val)=>
            _topic = @discoveryId + '/sensor/' + @hassDeviceId + "/state"
            _payload =
              variable: String val
            env.logger.debug "_stateTopic: " + _topic + ",  payload: " +  JSON.stringify(_payload)
            _options =
              qos : 1
            @client.publish(_topic, JSON.stringify(_payload), (err) =>
              if err
                env.logger.error "Error publishing state Variable  " + err
                reject()
              resolve()
            )
          .catch (err)=>
            env.logger.debug "handled error getting variable " + @_getVar + ", err: " + JSON.stringify(err,null,2)
        catch err
          env.logger.debug "handled error in @_getVar: " + @_getVar + ", err: " + JSON.stringify(err,null,2) 
      )

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      _options =
        qos : 0
      env.logger.debug "Publish status: " + _topic + ", _status: " + _status
      @client.publish(_topic, String _status) #, _options)

    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener @_variableName, @[@_handlerName]
        #@clearDiscovery()
        resolve()
      )

  module.exports = VariablesAdapter
