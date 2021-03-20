module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  util = require 'util'

  class SwitchAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      #@pimaticId = pimaticId
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @device_prefix = device_prefix
      @hassDeviceFriendlyName = device_prefix + ": " + device.id


      @stateHandler = (state) =>
        env.logger.debug "State change switch: " + state
        @_state = state
        @publishState()
      @device.on 'state', @stateHandler
      
      @device.getState()
      .then (state) =>
        @_state = state
        @publishDiscovery()
        env.logger.debug "Started SwitchAdapter #{@id}"
      .catch (err)=>
        env.logger.error "Error init SwitchAdapter " + err

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
      _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      _options =
        qos : 2
        retain: true
      @client.publish(_topic, null, _options)

    publishDiscovery: () =>
      _config = 
        name: @hassDeviceFriendlyName #@hassDeviceId
        unique_id: @hassDeviceId
        cmd_t: @discoveryId + '/' + @hassDeviceId + '/set'
        stat_t: @discoveryId + '/' + @hassDeviceId
        availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
        payload_available: "online"
        payload_not_available: "offline"

      _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
      env.logger.debug "Publish discovery #{@id}, topic: " + _topic + ", config: " + JSON.stringify(_config)
      _options =
        qos : 2
        retain: true
      @client.publish(_topic, JSON.stringify(_config), _options)

    publishState: () =>
      if @_state then _state = "ON" else _state = "OFF"
      _topic = @discoveryId + '/' + @hassDeviceId
      _options =
        qos : 0
      env.logger.debug "Publish state: " + _topic + ", _state: " + _state
      @client.publish(_topic, String(_state)) #, _options)

    update: () ->
      env.logger.debug "Update switch not implemented"

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
        qos : 2
        retain: true
      env.logger.debug "Publish switch status: " + _topic + ", status: " + _status
      @client.publish(_topic, String _status, _options)

    destroy: ->
      @device.removeListener 'state', @stateHandler if @stateHandler?
