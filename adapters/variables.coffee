module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = require("lodash")

  class VariablesAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discovery_prefix = discovery_prefix
      @hassDevices = {}

      for _variable in device.config.variables
        env.logger.debug "Adding variable: " + _variable.name
        @hassDevices[_variable.name] = new variableManager(@device, _variable, @client, @discovery_prefix)

    publishState: () =>
      for i, variable of @hassDevices
        variable.publishState()

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        publishDiscoveries = []
        for i, variable of @hassDevices
          publishDiscoveries.push variable.publishDiscovery()
          Promise.all(publishDiscoveries)
          resolve @id
        )
        
    
    clearDiscovery: () =>
      for i, variable of @hassDevices
        variable.clearDiscovery()

    handleMessage: (packet) =>
      for i, variable of @hassDevices
        variable.handlemessage(packet)

    update: (deviceNew) =>
      addHassDevices = []
      removeHassDevices = []
      for _variable in deviceNew.config.variables
        if !_.find(@hassDevices, (hassD) => hassD.variable.name == _variable.name )
          addHassDevices.push _variable
      for i, _hassdevice of @hassDevices
        if !_.find(deviceNew.config.variables, (v) => v.name == _hassdevice.variable.name)
          removeHassDevices.push _hassdevice

      for _hassDevice in removeHassDevices
        env.logger.debug "Removing variable " + _hassdevice.variable.name
        _hassDevice.destroy()
        delete @hassDevices[i]
      for _variable in addHassDevices
        env.logger.debug "Adding variable" + _variable.name
        _newVariableManager = new variableManager(@device, _variable, @client, @discovery_prefix)
        @hassDevices[_variable.name] = _newVariableManager
        @hassDevices[_variable.name].publishDiscovery()
        .then((_i) =>
          setTimeout( ()=>
            @hassDevices[_i].publishState()
          , 5000)
        ).catch((err) =>
        )

    destroy: ->
      for i,variable of @hassDevices
        variable.destroy()


  class variableManager extends events.EventEmitter

    constructor: (device, variable, client, discovery_prefix) ->  
      @name = device.name
      @id = device.id
      @device = device
      @variable = variable
      @unit = @device.attributes[@variable.name]?.unit ? @variable.name
      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device.id + "_" + @variable.name
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
      env.logger.debug "handlemessage sensor -> No action " + JSON.stringify(packet,null,2)
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
      _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      @client.publish(_topic, null, (err) =>
        if err
          env.logger.error "Error publishing Discovery Variable  " + err
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _configVar = 
          #name: @hassDeviceId
          name: @name + "." + @variable.name
          unique_id :@hassDeviceId
          state_topic: @discoveryId + '/sensor/' + @hassDeviceId + "/state"
          unit_of_measurement: @unit
          value_template: "{{ value_json.variable}}"
        _deviceClass = @getDeviceClass()
        if _deviceClass?
          _configVar["device_class"] = _deviceClass
        _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_configVar)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_configVar), _options,  (err) =>
          if err
            env.logger.error "Error publishing Discovery Variable  " + err
            reject()
          resolve(@variable.name)
        )
      )

    publishState: () =>
      return new Promise((resolve,reject) =>
        @device[@_getVar]()
        .then (val)=>
          _topic = @discoveryId + '/sensor/' + @hassDeviceId + "/state"
          _payload =
            variable: String val
          env.logger.debug "_stateTopic: " + _topic + ",  payload: " +  JSON.stringify(_payload)
          _options =
            qos : 1
          @client.publish(_topic, JSON.stringify(_payload), _options, (err) =>
            if err
              env.logger.error "Error publishing state Variable  " + err
              reject()
            resolve()
          )
      )

    destroy: ->
      @device.removeListener @_variableName, @[@_handlerName]
      @clearDiscovery()

  module.exports = VariablesAdapter
