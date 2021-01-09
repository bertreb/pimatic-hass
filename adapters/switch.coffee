module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class SwitchAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      #@pimaticId = pimaticId
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @hassDeviceFriendlyName = device_prefix + ": " + device.id

      @device.getState()
      .then (state) =>
        @_state = state
 
      @stateHandler = (state) =>
        env.logger.debug "State change switch: " + state
        @_state = state
        @publishState()
      @device.on 'state', @stateHandler

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      if (String _value) == "ON" then _newState = on else _newState = off
      unless @_state is _newState
        env.logger.debug "Action switch " + _value
        @device.changeStateTo(_newState)
        @_state = _newState
        #.then(()=>
        #  #@publishState()
        #).catch(()=>
        #)

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
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
          name: @hassDeviceFriendlyName #@hassDeviceId
          unique_id: @hassDeviceId
          cmd_t: @discoveryId + '/' + @hassDeviceId + '/set'
          stat_t: @discoveryId + '/' + @hassDeviceId
        _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
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
      if @_state then _state = "ON" else _state = "OFF"
      _topic = @discoveryId + '/' + @hassDeviceId
      _options =
        qos : 1
      env.logger.debug "Publish state: " + _topic + ", _state: " + _state
      @client.publish(_topic, String _state, _options)


    update: () ->
      env.logger.debug "Update not implemented"

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        @clearDiscovery()
        .then ()=>
          return @destroy()
        .then ()=>
          resolve()
        .catch (err) =>
          env.logger.debug "Error clear and destroy "
      )

    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener 'state', @stateHandler
        resolve()
      )
