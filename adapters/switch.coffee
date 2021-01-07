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
 
      @stateHandler = (state) =>
        env.logger.debug "State change switch: " + state
        @publishState()
      @device.on 'state', @stateHandler

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      if (String _value) == "ON" then _newState = on else _newState = off
      @device.getState()
      .then((state)=>
        unless _newState is state
          env.logger.debug "Action switch " + _value
          @device.changeStateTo(_newState)
          .then(()=>
            @publishState()
          ).catch(()=>
          )
      ).catch(()=>
      )

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/switch/' + @device.id + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, (err)=>
          if err
            env.logger.error "Error publishing Discovery " + err
            reject()
          resolve(@id)
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _config = 
          name: @device.id
          cmd_t: @pimaticId + '/' + @device.id + '/set'
          stat_t: @pimaticId + '/' + @device.id
        _topic = @discoveryId + '/switch/' + @device.id + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_config), _options, (err) =>
          if err
            env.logger.error "Error publishing Discovery " + err
            reject()
          resolve(@id)
        )
      )

    publishState: () =>
      @device.getState()
      .then((state)=>
        if state then _state = "ON" else _state = "OFF"
        _topic = @pimaticId + '/' + @device.id 
        _options =
          qos : 1
        env.logger.debug "Publish state: " + _topic + ", _state: " + _state
        @client.publish(_topic, String _state, _options)
      )

    update: () ->
      env.logger.debug "Update not implemented"

    clearAndDestroy: ->
      @clearDiscovery()
      .then () =>
        @device.removeListener 'state', @stateHandler

    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener 'state', @stateHandler
        resolve()
      )
