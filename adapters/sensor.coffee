module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = require("lodash")

  class SensorAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discovery_prefix = discovery_prefix
      @hassDevices = {}

      #env.logger.debug "Constructor AttributeAdapter: " + JSON.stringify(@device.attributes,null,2)
      for _a, _attribute of @device.attributes
        env.logger.debug "Adding attribute: " + _a
        @hassDevices[_a] = new attributeManager(@device, _a, @client, @discovery_prefix, device_prefix)

    publishState: () =>
      for i, _attribute of @hassDevices
        @hassDevices[i].publishState()

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        publishDiscoveries = []
        for i, _attribute of @hassDevices
          publishDiscoveries.push _attribute.publishDiscovery()
          Promise.all(publishDiscoveries)
          .then ()=>
            resolve @id
        )
        
    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        clears =[]
        destroys =[]
        for i, button of @hassDevices
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
      for i, _attribute of @hassDevices
        @hassDevices[i].clearDiscovery()

    handleMessage: (packet) =>
      for i, _attribute of @hassDevices
        @hassDevices[i].handleMessage(packet)

    update: (deviceNew) =>
      addHassDevices = []
      removeHassDevices = []

      for _a, _attribute of deviceNew.attributes
        if !_.find(@hassDevices, (hassD) => hassD.attributeName == _a )
          addHassDevices.push deviceNew.attributes[_a]
      removeHassDevices = _.differenceWith(@device.attributes,deviceNew.attributes, _.isEqual)
      for removeDevice in removeHassDevices
        env.logger.debug "Removing attribute " + removeDevice.name
        @hassDevices[removeDevice.name].clearDiscovery()
        .then ()=>
          @hassDevices[removeDevice.name].destroy()
          delete @hassDevices[removeDevice.name]

      @device = deviceNew
      for _attribute in addHassDevices
        env.logger.debug "Adding attribute" + _attribute.name
        @hassDevices[_attribute.name] = new attributeManager(deviceNew, _attribute, @client, @discovery_prefix, device_prefix)
        @hassDevices[_attribute.name].publishDiscovery()
        .then((_i) =>
          setTimeout( ()=>
            @hassDevices[_i].publishState()
          , 5000)
        ).catch((err) =>
        )

    destroy: ->
      return new Promise((resolve,reject) =>
        for i,_attribute of @hassDevices
          @hassDevices[i].destroy()
        resolve()
      )

  class attributeManager extends events.EventEmitter

    constructor: (device, attributeName, client, discovery_prefix, device_prefix) ->  
      @name = device.name
      @id = device.id
      @device = device
      @attributeName = attributeName
      @unit = @device.attributes[@attributeName].unit ? ""
      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @device_prefix = device_prefix
      @hassDeviceId = device_prefix+ "_" + device.id + "_" + @attributeName
      @hassDeviceFriendlyName = device_prefix + ": " + device.id + "." + @attributeName
      @_getVar = "get" + (@attributeName).charAt(0).toUpperCase() + (@attributeName).slice(1)
      env.logger.debug "@unit: " + @unit

      @_attributeName = @attributeName
      @_handlerName = @attributeName + "Handler"
      @[@_handlerName] = (val) =>
        env.logger.debug "Attribute '#{@attributeName}' change: " + val
        @publishState()
      @device.on @_attributeName, @[@_handlerName]
      env.logger.debug "Attribute constructor " + @name + ", handlerName: " + @_handlerName

    handleMessage: (packet) =>
      #env.logger.debug "handlemessage sensor -> No action" # + JSON.stringify(packet,null,2)
      return

    getDeviceClass: (_unit)=>
      if _unit is "hPa" or _unit is "mbar"
        @device_class = "pressure"
      else if _unit is "kWh" or _unit is "Wh" or _unit is "mWh"
        @device_class = "energy"
      else if _unit is "W" or _unit is "kW" or _unit is "mW"
        @device_class = "power"
      else if _unit is "lx" or _unit is "lm"
        @device_class = "illuminance"
      else if _unit is "A" or _unit is "kA" or _unit is "mA"
        @device_class = "current"
      else if _unit is "V" or _unit is "mV" or _unit is "kV"
        @device_class = "voltage"
      else if _unit is "°C" or _unit is "°F"
        @device_class = "temperature"
      else
        @device_class = null
      env.logger.debug "getDeviceClass: " + _unit + ", class: " + @device_class
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
        _deviceClass = @getDeviceClass(@unit)
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
          resolve(@attributeName)
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
                env.logger.error "Error publishing state attribute  " + err
                reject()
              resolve()
            )
          .catch (err)=>
            env.logger.debug "handled error getting attribute " + @_getVar + ", err: " + JSON.stringify(err,null,2)
        catch err
          env.logger.debug "handled error in @_getVar: " + @_getVar + ", err: " + JSON.stringify(err,null,2) 
      )

    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener @_attributeName, @[@_handlerName] 
        #@clearDiscovery()
        resolve()
      )

  module.exports = SensorAdapter
