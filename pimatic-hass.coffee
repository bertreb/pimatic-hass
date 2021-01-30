module.exports = (env) =>
  Promise = env.require 'bluebird'
  mqtt = require('mqtt')
  _ = require("lodash")
  switchAdapter = require('./adapters/switch')(env)
  alarmAdapter = require('./adapters/alarm')(env)
  buttonsAdapter = require('./adapters/buttons')(env)
  lightAdapter = require('./adapters/light')(env)
  #rgblightAdapter = require('./adapters/rgblight')(env)
  sensorAdapter = require('./adapters/sensor')(env)
  binarySensorAdapter = require('./adapters/binarysensor')(env)
  coverAdapter = require('./adapters/cover')(env)
  variablesAdapter = require('./adapters/variables')(env)
  #attributesAdapter = require('./adapters/attributes')(env)
  heatingThermostatAdapter = require('./adapters/thermostat')(env)

  class HassPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      @adapters = {}

      pluginConfigDef = require("./hass-config-schema.coffee")
      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('HassDevice', {
        configDef: deviceConfigDef.HassDevice,
        createCallback: (config, lastState) => new HassDevice(config, lastState, @framework, @)
      })


  class HassDevice extends env.devices.PresenceSensor

    constructor: (@config, lastState, @framework, @plugin) ->
      @id = @config.id
      @name = @config.name

      if @_destroyed then return

      @framework.on 'destroy', () =>
        for i, _adapter of @adapters
          if @adapters[i].setStatus?
            @adapters[i].setStatus(off)        

      # not possible, HassDevice need for this to be the last device in config.
      #for _d in @config.devices
      #  do(_d) =>
      #    if _d.indexOf(" ") >= 0
      #      env.logger.info "No spaced allowed in device id"
      #      throw new Error "No spaced allowed in device id" 

      @discovery_prefix = @plugin.config.discovery_prefix ? @plugin.pluginConfigDef.discovery_prefix.default
      @device_prefix = @plugin.config.device_prefix ? @plugin.pluginConfigDef.device_prefix.default
      @device_prefix_length = @device_prefix.length

      ###
      if @plugin.config.mqttProtocol == "MQTTS"
        #@mqttOptions["protocolId"] = "MQTTS"
        @mqttOptions["protocol"] = "mqtts"
        @mqttOptions.port = 8883
        @mqttOptions["keyPath"] = @plugin.config?.certPath or @plugin.configProperties.certPath.default
        @mqttOptions["certPath"] = @plugin.config?.keyPath or @plugin.configProperties.keyPath.default
        @mqttOptions["ca"] = @plugin.config?.caPath or @plugin.configProperties.caPath.default
      else
      ###

      #setTimeout( ()=>
      @framework.variableManager.waitForInit()
      .then ()=>
        @adapters = @plugin.adapters

        @mqttOptions =
          host: @plugin.config.mqttServer ? ""
          port: @plugin.config.mqttPort ? @plugin.pluginConfigDef.mqttPort.default
          username: @plugin.config.mqttUsername ? ""
          password: @plugin.config.mqttPassword ? ""
          clientId: 'pimatic_' + Math.random().toString(16).substr(2, 8)
          #protocolVersion: 4 # @plugin.config?.mqttProtocolVersion or 4
          #queueQoSZero: true
          keepalive: 180
          clean: true
          rejectUnauthorized: false
          reconnectPeriod: 15000
          debug: true # @plugin.config?.debug or false
        @mqttOptions["protocolId"] = "MQTT" # @config?.mqttProtocol or @plugin.configProperties.mqttProtocol.default

        @client = new mqtt.connect(@mqttOptions)
        env.logger.debug "Connecting to MQTT server..."

        @client.on 'connect', @clientConnectHandler = () =>
          env.logger.debug "Successfully connected to MQTT server"

          @client.subscribe @discovery_prefix + "/#" , (err, granted) =>
            if err
              env.logger.error "Error subscribing to topic " + err
              return
            env.logger.debug "Succesfully subscribed to #{@discovery_prefix}: " + JSON.stringify(granted,null,2)

            # check for to be added or deleted devices
            env.logger.debug "Checking for devices to added or removed"

            addHassDevices = []
            removeHassDevices = []

            for _deviceId in @config.devices
              if !_.find(@adapters, (deviceAdapter) => deviceAdapter.id == _deviceId )
                addHassDevices.push _deviceId
            for _deviceId, _device of @adapters
              if !_.find(@config.devices, (deviceC) => deviceC == _deviceId )
                removeHassDevices.push _deviceId

            if _.size(@config.devices) > 0
              @_setPresence(true)
            else
              @_setPresence(false)
            
            env.logger.debug "addHassDevices: " + JSON.stringify(addHassDevices,null,2)
            env.logger.debug "removeHassDevices: " + JSON.stringify(removeHassDevices,null,2)
            for _deviceId in removeHassDevices
              if @adapters[_deviceId]?
                env.logger.debug "Removing device: " + _deviceId
                @adapters[_deviceId].clearAndDestroy()
                .then ()=>
                  delete @adapters[_deviceId]
                .catch (err)=>
                  env.logger.debug "Device '#{_deviceId}' can't be removed " + err
              else
                env.logger.debug "Adapter does not exist: " + _deviceId

            for i, _adapter of @adapters
              if @adapters[i].setStatus?
                env.logger.debug "Restart Status on"
                @adapters[i].setStatus(on)        

            for _deviceId in addHassDevices
              _device = @framework.deviceManager.getDeviceById(_deviceId)
              if _device?
                do (_device) =>
                  env.logger.debug "Adding device: " + _device.id
                  @_addDevice(_device)
                  .then (_adapter)=>
                    env.logger.debug "_adapter added " + _device.id
                    @adapters[_device.id].publishDiscovery()
                    setTimeout ()=>
                      @adapters[_device.id].setStatus(on)
                      @adapters[_device.id].publishState()
                      env.logger.debug "Adapter initialized and published to Hass"
                    , 5000
                  .catch (err) =>
                    env.logger.debug "Device '#{_deviceId}' can't be added " + err
              else
                env.logger.debug "Device '#{_deviceId}' does not exist " + err

        @client.on  'message', @clientMessageHandler = (topic, message, packet) =>
          #env.logger.debug "message received with topic: " + (topic)
          if topic.startsWith(@discovery_prefix + "/status")
            if (String packet.payload).indexOf("offline") >= 0
              env.logger.info "Hass offline"
              @_setPresence(false)
            if (String packet.payload).indexOf("online") >= 0 
              env.logger.info "Hass online"
              @_setPresence(true)
              env.logger.debug "Republish, set status On and publish devices to Hass"
              for _i, _adapter of @adapters
                @adapters[_i].setStatus(on)
                @adapters[_i].publishState()
          else
            _adapterId = @getAdapterId(topic)
            if _adapterId?
              env.logger.debug "Adapter found for topic #{topic}, " +_adapterId + ", exists: " + @adapters[_adapterId]?
              @adapters[_adapterId].handleMessage(packet)

        # connection error handling
        @client.on 'close', @clientEndHandler = () => 
          @_setPresence(false)

        @client.on 'error', @clientErrorHandler = (err) => 
          env.logger.error "error: " + err
          @_setPresence(false)

        @client.on 'disconnect', @clientDisconnectHandler = () => 
          env.logger.info "Client disconnect"
          @_setPresence(false)

      @framework.on 'deviceRemoved', @deviceRemovedListener = (device) =>
        env.logger.debug "Device changed: " + device.config.id
        unless device.config.id is @id #This Hass device is changed via recreation
          if @adapters[device.config.id]?
            _device = device
            env.logger.debug "One of the used devices is deleted: " + _device.config.id
            @adapters[_device.config.id].clearAndDestroy()
            delete @adapters[_device.config.id]
            env.logger.debug "Adapter deleted for #{_device.id}"

      @framework.on 'deviceChanged', @deviceChangedListener = (device) =>
        env.logger.debug "Device changed: " + device.config.id
        unless device.config.id is @id #This Hass device is changed via recreation
          # one of the used device can be changed          
          if @adapters[device.config.id]?
            _device = device
            env.logger.debug "One of the used devices changed: " + _device.config.id
            @adapters[_device.config.id].clearAndDestroy()
            delete @adapters[_device.config.id]
            env.logger.debug "Adapter deleted for #{_device.id}"
            @_addDevice(_device)
            .then (_adapter)=>
              env.logger.debug "_adapter added " + _device.id
              @adapters[_device.id].publishDiscovery()
              setTimeout ()=>
                @adapters[_device.id].setStatus(on)
                @adapters[_device.id].publishState()
                env.logger.debug "Adapter initialized and published to Hass"
              , 5000

      super()

    _addDevice: (device) =>
      return new Promise((resolve,reject) =>
        if @adapters[device.id]?
          env.logger.debug "adapter already exists"
          resolve()
        #if device.config.class is "MilightRGBWZone" or device.config.class is "MilightFullColorZone"
        #  _newAdapter = new rgblightAdapter(device, @client, @discovery_prefix)
        #  @adapters[device.id] = _newAdapter
        #  resolve(_newAdapter)
        #env.logger.debug "_.size(device.attributes)>0 " + _.size(device.attributes)
        #env.logger.debug "Device in _addDevice: " + device.id
        if device.config.class is "DummyAlarmPanel"
          _newAdapter = new alarmAdapter(device, @client, @discovery_prefix, @device_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.DimmerActuator or (device.hasAttribute("dimlevel") and device.hasAttribute("state"))
          _newAdapter = new lightAdapter(device, @client, @discovery_prefix, @device_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.SwitchActuator
          _newAdapter = new switchAdapter(device, @client, @discovery_prefix, @device_prefix)
          env.logger.debug "Device.id: "+ device.id + ", newAdapter.id: " + _newAdapter.id
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device.config.class is "ButtonsDevice" or device.config.class is "ShellButtons"
          _newAdapter = new buttonsAdapter(device, @client, @discovery_prefix, @device_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.HeatingThermostat or (device.config.class).indexOf("Thermostat") >= 0
          _newAdapter = new heatingThermostatAdapter(device, @client, @discovery_prefix, @device_prefix, @)
          @adapters[device.id] = _newAdapter
          env.logger.debug "CHECKING: addAdapter device.id: #{device.id}"
          resolve(_newAdapter)
        else if device instanceof env.devices.ShutterController #device.config.class is "DummyShutter"
          _newAdapter = new coverAdapter(device, @client, @discovery_prefix, @device_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device.config.class is "VariablesDevice"
          _newAdapter = new variablesAdapter(device, @client, @discovery_prefix, @device_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if _.size(device.attributes)>0 
          _newAdapter = new sensorAdapter(device, @client, @discovery_prefix, @device_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else
          throw new Error "Init: Device type of device #{device.id} does not exist"
        #env.logger.info "Devices: " + JSON.stringify(@adapters,null,2)
        resolve()
      )

    getAdapterId: (topic) =>
      # topic is in format <@discovery_prefix>/<device prefix>_<device id>/...
      try
        unless topic.endsWith('/set')
          #env.logger.debug "Topic doesnt end with /set => no command, discard "
          return null
        _items = topic.split('/')
        unless _items[0] is @discovery_prefix
          env.logger.debug "Discovery prefix '#{@discovery_prefix}', not found:  " + _items[0]
          return null
        unless _items[1].startsWith(@device_prefix)
          env.logger.debug "Device_prefix '#{@device_prefix}', not found: " + _items[1]
          return null
        _startDeviceId = @device_prefix_length + 1 # counting from 0 + "_" + 1
        _deviceId = _items[1].substr(_startDeviceId)
        if _deviceId?
          env.logger.debug "Look for adapter for device: " + _deviceId
          env.logger.debug "Keys: " + _.keys(@adapters)
          _adapter = _.find(_.keys(@adapters), (k)=> _deviceId.indexOf(k)>= 0)
          if _adapter?
            env.logger.debug "Adapter found for device: " + _deviceId
            return _adapter
          else
            #env.logger.debug "Adapter for topic #{topic} not found"
            return null
        else
          #env.logger.debug "Adapter for topic #{topic} not found"
          return null
      catch err
        env.logger.error "Error getting adapter " + err
        return null

    destroy: () =>
      @framework.removeListener "deviceChanged", @deviceChangedListener
      @framework.removeListener "deviceRemoved", @deviceRemovedListener
      @client.removeListener 'connect', @clientConnectHandler
      @client.removeListener 'disconnect', @clientDisconnectHandler
      @client.removeListener 'message', @clientMessageHandler
      @client.removeListener 'error', @clientErrorHandler
      @client.removeListener 'end', @clientEndHandler
      @client.removeListener 'end', @clientEndHandler
      for i, _adapter of @adapters
        if @adapters[i].setStatus?
          @adapters[i].setStatus(off)

      super()

  return new HassPlugin
