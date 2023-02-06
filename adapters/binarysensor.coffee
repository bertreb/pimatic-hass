module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class BinarySensorAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client

      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @hassDeviceFriendlyName = device.name
      @discoveryId = discovery_prefix
      @hasContactSensor = false
      @hasPresenceSensor = false

      @publishDiscovery()

 
      @contactHandler = (contact) =>
        env.logger.debug "State change switch: " + contact
        @publishState()
      if @device.hasAttribute('contact')
        @hasContactSensor = true
        @device.on 'contact', @contactHandler

      @presenceHandler = (presence) =>
        env.logger.debug "State change switch: " + presence
        @publishState()
      if @device.hasAttribute('presence')
        @hasPresenceSensor = true
        @device.on 'presence', @presenceHandler
      
      ###
      @publishDiscovery()
      .then (id)=>
        return @setStatus(on)
      .then ()=>
        return @publishState()
      .finally ()=>
        env.logger.debug "Started BinarySensorAdapter #{@id}"
      .catch (err)=>
        env.logger.error "Error init BinarySensorAdapter " + err
      ###


    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      env.logger.debug "Action binary_sensor no action needed"

    clearDiscovery: () =>
      _options =
        qos : 2
        retain: true
      if @hasContactSensor
        _topic = @discoveryId + '/binary_sensor/' + @hassDeviceId + 'C/config'
        env.logger.debug "Discovery cleared #{@id} topic: " + _topic 
        @client.publish(_topic, null, _options)
      if @hasPresenceSensor
        _topic2 = @discoveryId + '/binary_sensor/' + @hassDeviceId + 'P/config'
        env.logger.debug "Discovery cleared {@id topic: " + _topic2 
        @client.publish(_topic2, null, _options)

    publishDiscovery: () =>
      if @hasContactSensor
        _configC = 
          name: @hassDeviceFriendlyName + " contact"
          unique_id: @hassDeviceId
          stat_t: @discoveryId + '/binary_sensor/' + @hassDeviceId + 'C/state'
          device_class: "opening"
          availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
          payload_available: "online"
          payload_not_available: "offline"
      
        _topic = @discoveryId + '/binary_sensor/' + @hassDeviceId + 'C/config'
        env.logger.debug "Publish discovery contact #{@id}, topic: " + _topic + ", config: " + JSON.stringify(_configC)
        _options =
          qos : 2
          retain: true
        @client.publish(_topic, JSON.stringify(_configC), _options)
      if @hasPresenceSensor
        _configP = 
          name: @hassDeviceFriendlyName + " motion"
          unique_id: @hassDeviceId
          stat_t: @discoveryId + '/binary_sensor/' + @hassDeviceId + 'P/state'
          device_class: "motion"
        _topic2 = @discoveryId + '/binary_sensor/' + @hassDeviceId + 'P/config'
        env.logger.debug "Publish discovery presence #{@id}, topic: " + _topic2 + ", config: " + JSON.stringify(_configP)
        _options =
          qos : 2
          retain: true
        @client.publish(_topic2, JSON.stringify(_configP), _options)

    publishState: () =>
      if @hasContactSensor
        @device.getContact()
        .then((contact)=>
          if contact then _state = "ON" else _state = "OFF"
          _topic = @discoveryId + '/binary_sensor/' + @hassDeviceId + 'C/state'
          env.logger.debug "Publish state contact: " + _topic + ", _state: " + _state
          _options =
            qos : 1
          @client.publish(_topic, String _state)
        )
      if @hasPresenceSensor
        @device.getPresence()
        .then((presence)=>
          if presence then _state = "ON" else _state = "OFF"
          _topic2 = @discoveryId + '/binary_sensor/' + @hassDeviceId + 'P/state'
          env.logger.debug "Publish state presence: " + _topic2 + ", _state: " + _state
          _options =
            qos : 0
          @client.publish(_topic2, String _state)
        )

    update: () ->
      env.logger.debug "Update not implemented"

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        @clearDiscovery()
        @destroy()
        resolve(@id)
      )

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      _options =
        retain: true
        qos : 2
      env.logger.debug "Publish status: " + _topic + ", status: " + _status
      @client.publish(_topic, String _status, _options)

    destroy: ->
      if @hasContactSensor
        @device.removeListener 'contact', @contactHandler
      if @hasPresenceSensor
        @device.removeListener 'presence', @presenceHandler
