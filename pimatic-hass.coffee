module.exports = (env) =>
  Promise = env.require 'bluebird'
  mqtt = require('mqtt')
  _ = require("lodash")
  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  #rgblightAdapter = require('./adapters/rgblight')(env)
  sensorAdapter = require('./adapters/sensor')(env)
  binarySensorAdapter = require('./adapters/binarysensor')(env)
  #shutterAdapter = require('./adapters/shutter')(env)
  variablesAdapter = require('./adapters/variables')(env)

  class HassPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>

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

      if @_destroyed
        return

      @framework.on 'destroy', () =>
        @destroy()
        #for i, _adapter of @adapters
        #  _adapter.setAvailability(off)        

      # not possible, HassDevice need for this to be the last device in config.
      for _d in @config.devices
        do(_d) =>
          if _d.indexOf(" ") >= 0
            env.logger.info "No spaced allowed in device id"
            throw new Error "No spaced allowed in device id" 

      @discovery_prefix = @plugin.config.discovery_prefix ? @plugin.pluginConfigDef.discovery_prefix.default

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

      @framework.variableManager.waitForInit()
      .then ()=>
        @client = new mqtt.connect(@mqttOptions)
        env.logger.debug "Connecting to MQTT server..."

        @client.on 'connect', () =>
          env.logger.debug "Successfully connected to MQTT server"
          @_initDevices()
          .then((nrOfDevices) =>
            if nrOfDevices > 0
              @_setPresence(true)
              @client.subscribe @discovery_prefix + "/#" , (err, granted) =>
                if err
                  env.logger.error "Error in initdevices " + err
                  return
                env.logger.debug "Succesfully subscribed to #{@discovery_prefix}: " + JSON.stringify(granted,null,2)
                for i, _adapter of @adapters
                  @adapters[i].publishDiscovery()
                  .then (_i)=>
                    setTimeout(()=>
                      @adapters[_i].publishState()
                    , 5000)
          ).catch((err)=>
            env.logger.error "Error initdevices: " + err
          )

        @client.on 'message', (topic, message, packet) =>
          #env.logger.debug "Packet received " + JSON.stringify(packet.payload,null,2)
          #if topic.endsWith("/config")
          #  env.logger.debug "Config received no action: " + String(packet.payload)
          #  return
          _adapter = @getAdapter(topic)
          #env.logger.debug "message received with topic: " + topic
          if _adapter?
            _adapter.handleMessage(packet)
          if topic.startsWith(@discovery_prefix + "/status")
            if (String packet.payload).indexOf("offline") >= 0
              @_setPresence(false)
            if (String packet.payload).indexOf("online") >= 0 
              @_setPresence(true)
              env.logger.debug "RePublish devices to Hass"
              @framework.variableManager.waitForInit()
              .then ()=>
                for i, _adpt of @adapters
                  env.logger.debug "Republish publishDiscovery: " + _adpt.name
                  @adapters[i].publishDiscovery()
                  .then (_i)=>
                    setTimeout(()=>
                      env.logger.debug "Republish publishState: " + _adpt.name
                      @adapters[_i].publishState()
                    , 5000)
            #env.logger.debug "Hass status message received, status: " + String packet.payload

        @client.on 'pingreq', () =>
          env.logger.debug "Ping request, answering with pingresp"
          # send a pingresp
          @client.pingresp()

        # connection error handling
        @client.on 'close', () => 
          @_setPresence(false)

        @client.on 'error', (err) => 
          env.logger.error "error: " + err
          @_setPresence(false)

        @client.on 'disconnect', () => 
          env.logger.info "Client disconnect"
          @_setPresence(false)


      @framework.on 'deviceRemoved', @deviceRemovedListener = (device) =>
      for i, _adapter of @adapters
        env.logger.debug "@adapters[i].id: " + @adapters[i].id + ", device.id: " + device.id
        if @adapters[i].id is device.id
          @adapters[i].clearAndDestroy()
          .then ()=>
            delete @adapters[i]

      @framework.on 'deviceChanged', @deviceChangedListener = (device) =>
        env.logger.debug "Device changed: " + device.config.id
        if device.config.id is @id
          # the HassDevice is changed
          env.logger.debug "HassDevice changed"
          ###
          #check if one of the used Hass is removed
          removeHassDevices = []
          env.logger.debug "device.config.devices: " + JSON.stringify(device.config.devices,null,2)
          for _device in @config.devices
            env.logger.debug "@config.devices.device: " + _device
            if !(_device in device.config.devices)
              env.logger.debug "added device '#{_device}' for removal"
              removeHassDevices.push _device
          for _removeDevice in removeHassDevices
            #remove 'device' from hass
            env.logger.debug "Remove device '#{_removeDevice}' from Hass"
            @adapters[_removeDevice].clearAndDestroy()
          ###
        else
          # one of the used device can be changed
          if @adapters[device.config.id]?
            env.logger.debug "One of the HassDevice changed: " + device.config.id
            @adapters[device.config.id].update(device)

      super()

    _addDevice: (device) =>
      return new Promise((resolve,reject) =>
        if @adapters[device.id]?
          reject("adapter already exists")
        #if device.config.class is "MilightRGBWZone" or device.config.class is "MilightFullColorZone"
        #  _newAdapter = new rgblightAdapter(device, @client, @discovery_prefix)
        #  @adapters[device.id] = _newAdapter
        #  resolve(_newAdapter)
        if device instanceof env.devices.DimmerActuator or (device.hasAttribute("dimlevel") and device.hasAttribute("state"))
          _newAdapter = new lightAdapter(device, @client, @discovery_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.SwitchActuator
          _newAdapter = new switchAdapter(device, @client, @discovery_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.Sensor and device.hasAttribute("temperature") and device.hasAttribute("humidity")
          _newAdapter = new sensorAdapter(device, @client, @discovery_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.Sensor and (device.hasAttribute("contact") or device.hasAttribute("presence"))
          _newAdapter = new binarySensorAdapter(device, @client, @discovery_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device.config.class is "VariablesDevice"
          _newAdapter = new variablesAdapter(device, @client, @discovery_prefix)
          @adapters[device.id] = _newAdapter
          resolve(_newAdapter)
        else if device instanceof env.devices.HeatingThermostat
          throw new Error "Device type HeatingThermostat not implemented"
        else if device instanceof env.devices.ShutterController
          throw new Error "Device type ShutterController not implemented"
        else
          throw new Error "Init: Device type of device #{device.id} does not exist"
        #env.logger.info "Devices: " + JSON.stringify(@adapters,null,2)
        reject()
      )

    _initDevices: () =>
      return new Promise((resolve,reject) =>
        @adapters = {}
        nrOfDevices = 0
        for _device,i in @config.devices
          env.logger.debug "InitDevices _device: " + _device
          device = @framework.deviceManager.getDeviceById(_device)
          if device?
            env.logger.debug "Found device: " + device.id
            do (device) =>
              nrOfDevices += 1
              @_addDevice(device)
              .then(()=>
                env.logger.debug "Device '#{device.id}' added"
              ).catch((err)=>
                env.logger.error "Error " + err
                reject()
              )
          else
            env.logger.info "Device '#{_device}' not found, please remove from config!"
        resolve(nrOfDevices)
      )

    getAdapter: (topic) =>
      try
        _items = topic.split('/')
        if _items[0] isnt @discovery_prefix
          env.logger.debug "#{@discovery_prefix} not found " + _items[0]
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
      try
        @framework.removeListener "deviceChanged", @deviceChangedListener
        @framework.removeListener "deviceRemoved", @deviceRemovedListener
      catch e
        env.logger.debug "HassDevice #{@id}, Error removing listeners"
      
      for i, _adapter of @adapters
        @adapters[i].clearAndDestroy()
        #.then ()=>
        delete @adapters[i]
      try
        @client.end()
      catch err
        env.logger.debug "HassDevice #{@id}, Error ending mqtt client"
      super()

  return new HassPlugin
