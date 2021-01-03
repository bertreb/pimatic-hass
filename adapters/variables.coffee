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
        env.logger.debug "Publish state of " + variable.id
        variable.publishState()

    publishDiscovery: () =>
      for i, variable of @hassDevices
        variable.publishDiscovery()
    
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
        _newVariableManager.publishDiscovery()
        .then(() =>
          _newVariableManager.publishState()
        ).catch((err) =>
        )

    destroy: ->
      for variable in @hassDevices
        variable.destroy()


  class variableManager extends events.EventEmitter

    constructor: (device, variable, client, discovery_prefix) ->
  
      @name = device.name
      @id = device.id
      @device = device
      @variable = variable
      @unit = @device.attributes[@variable.name].unit ? @attribute.name
      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device.id + "_" + @variable.name
      @_getVar = "get" + (@variable.name).charAt(0).toUpperCase() + (@variable.name).slice(1)
      #env.logger.debug "_getVar: " + @_getVar

      @variableHandler = (val) =>
        env.logger.debug "Variable change: " + val
        @publishState()
      @device.on @variable.name, @variableHandler

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
          @device_class = "none"
      return @device_class

    clearDiscovery: () =>
      _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      @client.publish(_topic, null)

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _configVar = 
          name: @hassDeviceId
          state_topic: @discoveryId + '/sensor/' + @hassDeviceId + "/state"
          unit_of_measurement: @unit
          device_class: @getDeviceClass()
          value_template: "{{ value_json.variable}}"
        _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_configVar)
        @client.publish(_topic, JSON.stringify(_configVar), (err) =>
          if err
            env.logger.error "Error publishing Discovery Variable  " + err
            reject()
          resolve()
        )
      )

    publishState: () =>
      @device[@_getVar]()
      .then (val)=>
        _topic = @discoveryId + '/sensor/' + @hassDeviceId + "/state"
        _payload =
            variable: val
        env.logger.debug "_stateTopic: " + _topic + ",  payload: " +  JSON.stringify(_payload)
        @client.publish(_topic, JSON.stringify(_payload))
      .catch (err) =>
        env.logger.info "Error getting Humidity: " + err

    destroy: ->
      @clearDiscovery()
      @device.removeListener @variable.name, @variableHandler

  module.exports = VariablesAdapter
