module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class LightAdapter extends events.EventEmitter

    constructor: (device, client, pimaticId) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @pimaticId = pimaticId
      @discoveryId = pimaticId
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
        env.logger.info "_parsedValue.state: " + JSON.stringify(_parsedValue)
      catch err
        env.logger.error "No valid json received " + err
        return

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
      _topic = @discoveryId + '/light/' + @device.id + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      @client.publish(_topic, null)

    publishDiscovery: () =>
      _config = 
        name: @device.id
        cmd_t: @discoveryId + '/' + @device.id + '/set'
        stat_t: @discoveryId + '/' + @device.id + '/state'
        schema: "json"
        brightness: true
        #brightness_state_topic: @discoveryId + '/' + @device.id + '/brightness'
        #brightness_command_topic: @discoveryId + '/' + @device.id + '/brightness/set'
      _topic = @discoveryId + '/light/' + @device.id + '/config'
      env.logger.debug "Publish discover _topic: " + _topic 
      env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
      @client.publish(_topic, JSON.stringify(_config), (err) =>
        if err
          env.logger.error "Error publishing Discovery " + err
      )

    publishState: () =>
      @device.getState()
      .then((state)=>
        if state then _state = "ON" else _state = "OFF"
        _topic = @pimaticId + '/' + @device.id + '/status'
        env.logger.debug "Publish state: " + _topic + ", _state: " + _state
        @device.getDimlevel()
        .then((dimlevel)=>
          _topic = @pimaticId + '/' + @device.id + '/state'
          _dimlevel = map(dimlevel,0,100,0,255)
          _payload =
            state: _state
            brightness: _dimlevel
          env.logger.debug "Publish light payload: " + JSON.stringify(_payload)
          @client.publish(_topic, JSON.stringify(_payload))
        )
      )

    map = (value, low1, high1, low2, high2) ->
      Math.round(low2 + (high2 - low2) * (value - low1) / (high1 - low1))

    destroy: ->
      @clearDiscovery()
      @device.removeListener 'state', @stateHandler
      @device.removeListener 'dimlevel', @dimlevelHandler
