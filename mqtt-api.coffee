module.exports = (env) =>
  Promise = env.require 'bluebird'
  mqtt = require('mqtt')
  _ = require("lodash")
  switchAdapter = require('./adapters/switch')(env)
  #lightAdapter = require('./adapters/light')(env)
  #buttonAdapter = require('./adapters/button')(env)
  #shutterAdapter = require('./adapters/shutter')(env)

  class MqttApiPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      pluginConfigDef = require("./mqtt-api-config-schema.coffee")
      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('MqttApiDevice', {
        configDef: deviceConfigDef.MqttApiDevice,
        createCallback: (config, lastState) => new MqttApiDevice(config, lastState, @framework, @)
      })


  class MqttApiDevice extends env.devices.PresenceSensor

    constructor: (@config, lastState, @framework, @plugin) ->
      @id = @config.id
      @name = @config.name

      if @_destroyed
        return

      @framework.on 'destroy', () =>
        for i, _adapter of @adapters
          _adapter.setAvailability(off)        

      for _d in @config.devices
        do(_d) =>
          _d = _d.trim()
          _dev = @framework.deviceManager.getDeviceById(_d)
          unless _dev?
            throw new Error ("Pimatic device #{_d} does not exsist")

      @hassTopic = @plugin.config.hassTopic ? @plugin.pluginConfigDef.hassTopic.default

      @mqttOptions =
          host: @plugin.config.mqttServer ? ""
          port: @plugin.config.mqttPort ? @plugin.pluginConfigDef.mqttPort.default
          username: @plugin.config.mqttUsername ? ""
          password: @plugin.config.mqttPassword ? ""
          clientId: 'pimatic_' + Math.random().toString(16).substr(2, 8)
          #protocolVersion: 4 # @plugin.config?.mqttProtocolVersion or 4
          #queueQoSZero: true
          #keepalive: 180
          #clean: true
          rejectUnauthorized: false
          reconnectPeriod: 15000
          debug: true # @plugin.config?.debug or false
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
      @mqttOptions["protocolId"] = "MQTT" # @config?.mqttProtocol or @plugin.configProperties.mqttProtocol.default

      @client = new mqtt.connect(@mqttOptions)
      env.logger.debug "Connecting to MQTT server..."

      unless @client.connected
        @client.on 'connect', () =>
          env.logger.debug "Successfully connected to MQTT server"
          @_initDevices()
          .then(() =>
            @_setPresence(true)
            @client.subscribe @hassTopic + "/#" , (err, granted) =>
              if err
                env.logger.error "Error in initdevices " + err
                return
              env.logger.debug "Succesfully subscribed to #{@hassTopic}: " + JSON.stringify(granted,null,2)
              for i, _adapter of @adapters
                _adapter.publishDiscovery()
          ).catch((err)=>
            env.logger.error "Error initdevices: " + err
          )

      @client.on 'message', (topic, message, packet) =>
        if topic.endsWith("/config")
          env.logger.debug "Config received no action"
          return
        _adapter = @getAdapter(topic)
        env.logger.debug "message received with topic: " + topic
        if _adapter?
          #env.logger.info "_adapter2: " + _adapter
          newState = _adapter.handleMessage(packet)

      @client.on 'pingreq', () =>
        env.logger.debug "Ping request, no aswer YET"
        # send a pingresp
        #@client.pingresp()

      # connection error handling
      @client.on 'close', () => 
        @_setPresence(false)

      @client.on 'error', (err) => 
        env.logger.error "error: " + err
        @_setPresence(false)

      @client.on 'disconnect', () => 
        env.logger.info "Client disconnect"
        @_setPresence(false)


      @framework.on 'deviceDeleted', (device) =>
      for i, _adapter of @adapters
        if _adapter.id is device.id
          _adapter.destroy()
          delete @adapters[i]

      @framework.on 'deviceAdded', (device) =>
        return
        @framework.variableManager.waitForInit()
        .then(() =>
          env.logger.info "Device '#{device.id}' checked for autodiscovery"
          unless @adapters[device.id]?
            @_addDevice(device)
            .then((newAdapter) =>
              env.logger.info "Device '#{newAdapter.id}' added"
              newAdapter.publishDiscovery()
            ).catch((err)=>
            )
        ).catch((err) =>
        )

      super()


    _addDevice: (device) =>
      return new Promise((resolve,reject) =>
        env.logger.info "AddDevice1: " + device.id
        if device instanceof env.devices.DimmerActuator
          #device type implemented
        else if device instanceof env.devices.SwitchActuator
          env.logger.info "AddDevice2: " + device.id
          unless @client?
            env.logger.info "Can add adapter, @client inknown"
            reject()
          _newAdapter = new switchAdapter(device, @client, @hassTopic)
          if @adapters[device.id]?
            @adapters[device.id].destroy()
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.ButtonsDevice
          #device type implemented
        else if device instanceof env.devices.HeatingThermostat
          #throw new Error "Device type HeatingThermostat not implemented"
        else if device instanceof env.devices.ShutterController
          #throw new Error "Device type ShutterController not implemented"
        else
          #throw new Error "Init: Device type of device #{_device.id} does not exist"
        #env.logger.info "Devices: " + JSON.stringify(@adapters,null,2)
        reject()
      )

    _initDevices: () =>
      return new Promise((resolve,reject) =>
        @adapters = {}
        for _device,i in @config.devices
          env.logger.info "device: " + _device
          device = @framework.deviceManager.getDeviceById(_device)
          unless device?
            env.logger.debug 'No devices found!'
            reject()
          do (device) =>
            if @adapters[device.id]?
              @adapter[device.id].destroy()
            #check device is part of exposed plugins (not yet)
            if device instanceof env.devices.DimmerActuator
              #device type implemented
            else if device instanceof env.devices.SwitchActuator
              @adapters[device.id] = new switchAdapter(device, @client, @hassTopic)
              env.logger.debug "Adapter for device #{device.id} created"
              #resolve()
            else if device instanceof env.devices.ButtonsDevice
              #device type implemented
            else if device instanceof env.devices.HeatingThermostat
              #throw new Error "Device type HeatingThermostat not implemented"
            else if device instanceof env.devices.ShutterController
              #throw new Error "Device type ShutterController not implemented"
            else
              #throw new Error "Init: Device type of device #{_device.id} does not exist"
            #env.logger.info "Devices: " + JSON.stringify(@adapters,null,2)
        resolve()
      )

    getAdapter: (topic) =>
      try
        _items = topic.split('/')
        if _items[0] isnt @hassTopic
          env.logger.debug "hassTopic not found " + _items[0]
          return null
        if _items[1]?
          _adapter = @adapters[_items[1]]
          if !_adapter?
            env.logger.debug "Device '#{__items[1]}'' not found"
          else
            return @adapters[_items[1]]
        else
          return null
      catch err
        return null

    destroy: () =>
      for i, _adapter of @adapters
        _adapter.destroy()
        #delete @adapters[i]
      #@client.end()
      super()

  return new MqttApiPlugin
