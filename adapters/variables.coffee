module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = require("lodash")
  BaseMultiSensor = require("./base.coffee")(env)

  class VariablesAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discovery_prefix = discovery_prefix

      #@publishDiscovery()

      @hassDevices = {}

      #for _variable in device.config.variables
      #  env.logger.debug "Adding variable: " + _variable.name
      #  @hassDevices[_variable.name] = new variableManager(@device, _variable, @client, discovery_prefix, device_prefix)
      Promise.each(device.config.variables, (_variable)=>
        env.logger.debug "Adding variable: " + _variable.name
        @hassDevices[_variable.name] = new variableManager(@device, _variable, @client, @discovery_prefix, device_prefix)
      )
      .then ()=>
        @publishDiscovery()
      #  @setStatus(on)
      #  @publishState()
      ###
      .finally ()=>
        env.logger.debug "Started VariablesAdapter #{@id}"
      .catch (err)=>
        env.logger.error "Error init VariablesAdapter " + err
      ###

    publishState: () =>
      for i, variable of @hassDevices
        @hassDevices[i].publishState()

    publishDiscovery: () =>
      for i, variable of @hassDevices
        @hassDevices[i].publishDiscovery()

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        for i, variable of @hassDevices
          @hassDevices[i].clearDiscovery()
        for i, variable of @hassDevices
          @hassDevices[i].destroy()
        resolve()
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
      for i, variable of @hassDevices
        @hassDevices[i].setStatus(online)

    destroy: ->
      for i,variable of @hassDevices
        @hassDevices[i].destroy()


  class variableManager extends BaseMultiSensor

    constructor: (device, variable, client, discovery_prefix, device_prefix) ->  
      @name = device.name
      @id = device.id
      @device = device
      @variable = variable
      @unit = @device.attributes[@variable.name]?.unit ? ""
      @label = @device.attributes[@attributeName]?.label ? null
      @acronym = @device.attributes[@attributeName]?.acronym ? null
      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id + "_" + @variable.name
      @hassDeviceFriendlyName = device.name + "." + @variable.name
      @_getVar = "get" + (@variable.name).charAt(0).toUpperCase() + (@variable.name).slice(1)
      env.logger.debug "Init variable Manager " + @id

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

    ###
    getDeviceClass: (_attribute, _unit, _label, _acronym)=>

      if !_unit and !_label and !_acronym and !_attribute then return null

      fields = []
      if _attribute? then fields.push _attribute.toLowerCase()
      if _unit? then fields.push _unit.toLowerCase()
      if _label? then fields.push _label.toLowerCase()
      if _acronym? then fields.push _acronym.toLowerCase()

      pressures = ['hpa','mbar',"pressure"]
      watts = ["w","kw","mw","watt","power"]
      energies = ['kwh','wh','mwh',"watt"]
      luminances = ["lx","lm","luminace"]
      amperes = ["a","ma","ampere", "ka","current"]
      volts = ["v", "mv", "kv", "volt","voltage"]
      temperatures = ["°c","°f","celsius","fahrenheit","temperature"]
      humidities = ["hum","humidity"]
      signals = ["wifi","db","dbm"]
      batteries = ["batt","battery"]
      timestamps = ["date","time","timestamp"]

      if _.find(fields,(f)=> f in pressures) 
        @device_class = "pressure"
      else if _.find(fields,(f)=> f in energies)
        @device_class = "energy"
      else if _.find(fields,(f)=> f in watts)
        @device_class = "power"
      else if _.find(fields,(f)=> f in luminances)
        @device_class = "illuminance"
      else if _.find(fields,(f)=> f in amperes)
        @device_class = "current"
      else if _.find(fields,(f)=> f in volts)
        @device_class = "voltage"
      else if _.find(fields,(f)=> f in temperatures)
        @device_class = "temperature"
      else if _.find(fields,(f)=> f in humidities)
        @device_class = "humidity"
      else if _.find(fields,(f)=> f in signals)
        @device_class = "signal_strength"
      else if _.find(fields,(f)=> f in batteries)
        @device_class = "battery"
      else if _.find(fields,(f)=> f in timestamps)
        @device_class = "timestamp"
      else
        @device_class = null
      env.logger.debug "getDeviceClass: " + _unit + ", class: " + @device_class
      return @device_class
    ###

    clearDiscovery: () =>
      _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      _options =
        qos : 2
        retain: true
      @client.publish(_topic, null, _options)

    publishDiscovery: () =>
      _configVar = 
        name: @hassDeviceFriendlyName
        unique_id :@hassDeviceId
        state_topic: @discoveryId + '/sensor/' + @hassDeviceId + "/state"
        value_template: "{{ value_json.variable}}"
        availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
        payload_available: "online"
        payload_not_available: "offline"
      _deviceClass = @getDeviceClass(@attributeName, @unit, @label, @acronym)
      _configVar["device_class"] = _deviceClass if _deviceClass?
      _configVar["unit_of_measurement"] = @unit if @unit?
      _topic = @discoveryId + '/sensor/' + @hassDeviceId + '/config'
      env.logger.debug "Publish discovery #{@id}, topic: " + _topic + ", config: " + JSON.stringify(_configVar)
      _options =
        retain : true
        qos: 2
      @client.publish(_topic, JSON.stringify(_configVar), _options)

    publishState: () =>
      try
        @device[@_getVar]()
        .then (val)=>
          _topic = @discoveryId + '/sensor/' + @hassDeviceId + "/state"
          _payload =
            variable: String val
          env.logger.debug "PublishState: " + _topic + ",  payload: " +  JSON.stringify(_payload)
          _options =
            retain : true
          @client.publish(_topic, JSON.stringify(_payload), _options)
        .catch (err)=>
          env.logger.debug "handled error getting variable " + @_getVar + ", err: " + JSON.stringify(err,null,2)
      catch err
        env.logger.debug "handled error in @_getVar: " + @_getVar + ", err: " + JSON.stringify(err,null,2) 

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      _options =
        retain : true
        qos: 2
      env.logger.debug "Publish status: " + _topic + ", status: " + _status
      @client.publish(_topic, String _status, _options)

    destroy: ->
      @device.removeListener @_variableName, @[@_handlerName] if  @[@_handlerName]?

  module.exports = VariablesAdapter
