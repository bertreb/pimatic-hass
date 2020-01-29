module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class SwitchAdapter extends events.EventEmitter

    constructor: (device, client, pimaticId) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @pimaticId = pimaticId
      @discoveryId = pimaticId
      @device.getState()
      .then((state)=>
        @_state = state
        @setAvailability(on)
      ).catch((err) =>
      )
      @_availability = "online"
      #@publishState(@_state)
      #env.logger.debug "Initiatal state switch: " + @_state

      @stateHandler = (state) =>
        env.logger.debug "State change switch: " + state
        if @_state isnt state
          @_state = state
          @publishState(state)
      @device.on 'state', @stateHandler

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      _value = 0
      _action = String packet.payload
      env.logger.debug "Action switch " + _action
      switch _action
        when "ON"
          @device.changeStateTo(on)
          @_state = true
        when "OFF"
          @device.changeStateTo(off)
          @_state = false
        else
          env.logger.debug "Action '#{_action}' unknown"
      return @_state

    clearDiscovery: () =>
      _topic = @discoveryId + '/switch/' + @device.id + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      @client.publish(_topic, null)

    publishDiscovery: () =>
      _config = 
        name: @device.id
        cmd_t: @pimaticId + '/' + @device.id + '/set'
        stat_t: @pimaticId + '/' + @device.id + '/state'
        avty_t: @pimaticId + '/' + @device.id + '/availability'
      _topic = @discoveryId + '/switch/' + @device.id + '/config'
      env.logger.debug "Publish discover _topic: " + _topic 
      env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
      @client.publish(_topic, JSON.stringify(_config), (err) =>
        if err
          env.logger.error "Error publishing Discovery " + err
      )

    publishState: (state) =>
      unless state? then state = @_state
      if state then _state = "ON" else _state = "OFF"
      _topic = @pimaticId + '/' + @device.id + '/state'
      env.logger.debug "_stateTopic: " + _topic + ", _state: " + _state
      @client.publish(_topic, _state)

    publishSet: (state) =>
      unless state? then state = @_state
      if state then _state = "ON" else _state = "OFF"
      _topic = @pimaticId + '/' + @device.id + '/set'
      env.logger.debug "_setTopic: " + _topic + ", _state: " + _state
      @client.publish(_topic, _state)

    setAvailability: (state) =>
      unless state? then state = @_availability
      @_availability = state
      if state then _state = "online" else _state = "offline"
      _topic = @pimaticId + '/' + @device.id + '/availability'
      env.logger.debug "_setAvailablitity: " + _topic + ", availability: " + _state
      @client.publish(_topic, _state)

    destroy: ->
      @clearDiscovery()
      @device.removeListener 'state', @stateHandler
