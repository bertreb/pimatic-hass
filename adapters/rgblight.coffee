module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  Color = require('color')

  class RGBLightAdapter extends events.EventEmitter

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

      @hueHandler = (hue) =>
        env.logger.debug "Hue change dimmer: " + hue
        @publishState()
      @device.on 'hue', @hueHandler


    handleMessage: (packet) =>
      #env.logger.debug "Handlemessage packet: " + JSON.stringify(packet,null,2)
      _items = (packet.topic).split('/')
      _command = _items[2]
      _value = packet.payload

      env.logger.debug "Action handlemessage rgblight " + _command + ", value " + _value
      switch _command
        when "brightness"
          _newDimlevel = map((Number _value),0,255,0,100)
          @device.getDimlevel()
          .then((dimlevel) =>
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
        when "switch"
          if (String _value) == "ON" then _newState = on else _newState = off
          @device.getState()
          .then((state)=>
            unless _newState is state
              if _newState is on then @device.changeDimlevelTo(100)
              if _newState is off then @device.changeDimlevelTo(0)
              @device.changeStateTo(_newState)
              .then(()=>
                @publishState()
              ).catch(()=>
              )
          ).catch(()=>
          )
        when "rgb"
          env.logger.info "RGB: " + String Buffer.from(_value)
          _newHue = (Color.rgb(_value)).hue()
          env.logger.info "HUE: " + _newHue
          return
          @device.getHue()
          .then((hue) =>
            unless _newHue is hue
              @device.changeHueTo(_newHue)
              .then(()=>
                @publishState()
              ).catch(()=>
              )
          )
        else
          env.logger.debug "Action '#{_command}' unknown"
      return

    clearDiscovery: () =>
      _topic = @discoveryId + '/light/' + @device.id + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      @client.publish(_topic, null)

    publishDiscovery: () =>
      _config = 
        name: @device.id
        cmd_t: @discoveryId + '/' + @device.id + '/switch'
        stat_t: @discoveryId + '/' + @device.id + '/status'
        brightness_state_topic: @discoveryId + '/' + @device.id + '/brightness'
        brightness_command_topic: @discoveryId + '/' + @device.id + '/brightness/set'
        rgb_state_topic: @discoveryId + '/' + @device.id + '/rgb'
        rgb_command_topic: @discoveryId + '/' + @device.id + '/rgb/set'
        #state_value_template: "{{ value_json.state }}"
        #brightness_value_template: "{{ value_json.brightness }}"
        #rgb_value_template: "{{ value_json.rgb | join(',') }}"
        #optimistic: false
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
        _topic = @pimaticId + '/' + @device.id  + '/status'
        env.logger.debug "Publish state: " + _topic + ", _state: " + _state
        @client.publish(_topic, String _state)
      )
      @device.getDimlevel()
      .then((dimlevel)=>
        _topic2 = @pimaticId + '/' + @device.id + '/brightness'
        _dimlevel = map(dimlevel,0,100,0,255)
        env.logger.debug "Publish dimlevel: " + _topic2 + ", _dimlevel: " + _dimlevel
        @client.publish(_topic2, String _dimlevel)
      )
      return
      @device.getHue()
      .then((hue)=>
        _topic3 = @pimaticId + '/' + @device.id + '/rgb'
        _hue = hue # map(dimlevel,0,100,0,255)
        env.logger.debug "Publish dimlevel: " + _topic3 + ", hue: " + JSON.stringify(_hue)
        _payload = 
          rgb: 
            r: 127
            g: 0
            b: 200
        @client.publish(_topic3, Buffer.from(_payload))
      )

    map = (value, low1, high1, low2, high2) ->
      Math.round(low2 + (high2 - low2) * (value - low1) / (high1 - low1))

    destroy: ->
      @clearDiscovery()
      @device.removeListener 'state', @stateHandler
      @device.removeListener 'dimlevel', @dimlevelHandler
      @device.removeListener 'hue', @hueHandler
