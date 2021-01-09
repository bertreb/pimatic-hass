module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class LightAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @hassDeviceFriendlyName = device_prefix + ": " + device.id

      @publishState()

      @dimlevelHandler = (dimlevel) =>
        env.logger.debug "dimlevel change dimmer: " + dimlevel
        @publishState()
      @device.on 'dimlevel', @dimlevelHandler

      @stateHandler = (state) =>
        env.logger.debug "State change dimmer: " + state
        @publishState()
      @device.on 'state', @stateHandler

    handleMessage: (packet) =>
      #env.logger.debug "Handlemessage packet: " + JSON.stringify(packet,null,2)
      _items = (packet.topic).split('/')
      _command = _items[2]
      _value = packet.payload

      env.logger.debug "Action handlemessage rgblight " + _command + ", value " + _value
      try
        _parsedValue = JSON.parse(_value)
        env.logger.debug "_parsedValue.state: " + JSON.stringify(_parsedValue)
      catch err
        env.logger.debug "No valid json received " + err
        _parsedValue = _value

      if _command == "set"
        if _parsedValue.state?
          if (String _parsedValue.state) == "ON" then _newState = on else _newState = off
          @device.getState()
          .then((state)=>
            env.logger.info "_newState: " + _newState + ", state: " + state
            unless _newState is state
              if _newState is on then @device.changeDimlevelTo(100)
              if _newState is off then @device.changeDimlevelTo(0)
              @device.changeStateTo(_newState)
              .then(()=>
                @publishState()
              ).catch(()=>
              )
          ).catch((err)=>
            env.logger.error "Error in getState: " + err
          )
        else
          env.logger.info "no handling yet"
        
        if _parsedValue.brightness?
          _newDimlevel = map((Number _parsedValue.brightness),0,255,0,100)
          @device.getDimlevel()
          .then((dimlevel) =>
            env.logger.info "_newDimlevel: " + _newDimlevel + ", dimlevel: " + dimlevel
            unless _newDimlevel is dimlevel
              @device.getState()
              .then((state)=>
                if _newDimlevel is 0 and state is on then @device.changeStateTo(off)
                if _newDimlevel > 0 and state is off then @device.changeStateTo(on)
                @device.changeDimlevelTo(_newDimlevel)
                .then(()=>
                  @publishState()
                )
              )
          ).catch((err)=>
          )

      return

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/light/' + @hassDeviceId + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, ()=>
          resolve()
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _config = 
          name: @hassDeviceFriendlyName
          unique_id: @hassDeviceId
          cmd_t: @discoveryId + '/' + @hassDeviceId + '/set'
          stat_t: @discoveryId + '/' + @hassDeviceId + '/state'
          schema: "json"
          brightness: true
          #brightness_state_topic: @discoveryId + '/' + @device.id + '/brightness'
          #brightness_command_topic: @discoveryId + '/' + @device.id + '/brightness/set'
        _topic = @discoveryId + '/light/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_config), _options, (err) =>
          if err
            env.logger.error "Error publishing Discovery " + err
        )
        resolve(@id)
      )

    publishState: () =>
      @device.getState()
      .then((state)=>
        if state then _state = "ON" else _state = "OFF"
        _topic = @discoveryId + '/' + @hassDeviceId + '/status'
        env.logger.debug "Publish state: " + _topic + ", _state: " + _state
        @device.getDimlevel()
        .then((dimlevel)=>
          _topic = @discoveryId + '/' + @hassDeviceId + '/state'
          _dimlevel = map(dimlevel,0,100,0,255)
          _payload =
            state: _state
            brightness: _dimlevel
          env.logger.debug "Publish light payload: " + JSON.stringify(_payload)
          _options =
            qos : 1
          @client.publish(_topic, JSON.stringify(_payload), _options)
        )
      )

    map = (value, low1, high1, low2, high2) ->
      Math.round(low2 + (high2 - low2) * (value - low1) / (high1 - low1))

    update: () ->
      env.logger.debug "Update not implemented"

    clearAndDestroy: ->
      @clearDiscovery()
      .then () =>
        @destroy()

    destroy: ->
      return new Promise((resolve,reject) =>      
        @device.removeListener 'state', @stateHandler
        @device.removeListener 'dimlevel', @dimlevelHandler
        resolve()
      )
