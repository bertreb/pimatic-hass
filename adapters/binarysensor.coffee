module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class BinarySensorAdapter extends events.EventEmitter

    constructor: (device, client, pimaticId) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @pimaticId = pimaticId
      @discoveryId = pimaticId
      @hasContactSensor = false
      @hasPresenceSensor = false
 
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

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      env.logger.debug "Action binary_sensor no action needed"

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        if @hasContactSensor
          _topic = @discoveryId + '/binary_sensor/' + @device.id + 'C/config'
          env.logger.debug "Discovery cleared _topic: " + _topic 
          @client.publish(_topic, null)
        if @hasPresenceSensor
          _topic2 = @discoveryId + '/binary_sensor/' + @device.id + 'P/config'
          env.logger.debug "Discovery cleared _topic: " + _topic2 
          @client.publish(_topic2, null)
        resolve()
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        if @hasContactSensor
          _configC = 
            name: @device.id
            stat_t: @pimaticId + '/binary_sensor/' + @device.id + 'C/state'
            device_class: "opening"
          _topic = @discoveryId + '/binary_sensor/' + @device.id + 'C/config'
          env.logger.debug "Publish discover _topic: " + _topic 
          env.logger.debug "Publish discover _configContact: " + JSON.stringify(_configC)
          _options =
            qos : 1
          @client.publish(_topic, JSON.stringify(_configC), _options, (err) =>
            if err
              env.logger.error "Error publishing Discovery " + err
          )
        if @hasPresenceSensor
          _configP = 
            name: @device.id
            stat_t: @pimaticId + '/binary_sensor/' + @device.id + 'P/state'
            device_class: "motion"
          _topic2 = @discoveryId + '/binary_sensor/' + @device.id + 'P/config'
          env.logger.debug "Publish discover _topic: " + _topic2
          env.logger.debug "Publish discover _configPresence: " + JSON.stringify(_configP)
          _options =
            qos : 1
          @client.publish(_topic2, JSON.stringify(_configP), _options, (err) =>
            if err
              env.logger.error "Error publishing Discovery " + err
          )
        resolve(@id)
      )

    publishState: () =>
      if @hasContactSensor
        @device.getContact()
        .then((contact)=>
          if contact then _state = "ON" else _state = "OFF"
          _topic = @pimaticId + '/binary_sensor/' + @device.id + 'C/state'
          env.logger.debug "Publish contact: " + _topic + ", _state: " + _state
          _options =
            qos : 1
          @client.publish(_topic, String _state, _options)
        )
      if @hasPresenceSensor
        @device.getPresence()
        .then((presence)=>
          if presence then _state = "ON" else _state = "OFF"
          _topic2 = @pimaticId + '/binary_sensor/' + @device.id + 'P/state'
          env.logger.debug "Publish presence: " + _topic2 + ", _state: " + _state
          _options =
            qos : 1
          @client.publish(_topic2, String _state, _options)
        )

    update: () ->
      env.logger.debug "Update not implemented"

    clearAndDestroy: ->
      @clearDiscovery()
      .then () =>
        @destroy()

    destroy: ->
      return new Promise((resolve,reject) =>
        if @hasContactSensor
          @device.removeListener 'contact', @contactHandler
        if @hasPresenceSensor
          @device.removeListener 'presence', @presenceHandler
        resolve()
      )
