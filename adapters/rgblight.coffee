module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  convert = require('color-convert')

  class RGBLightAdapter extends events.EventEmitter

    constructor: (device, client, pimaticId) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @pimaticId = pimaticId
      @discoveryId = pimaticId

      @saturation = 0
      @lightness = 0
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
        @hueEventTriggered = true
        @publishState()
      @device.on 'hue', @hueHandler


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
    
        if _parsedValue.color?
          _newHexColor = convert.rgb.hex(_parsedValue.color.r,_parsedValue.color.g,_parsedValue.color.b)
          _newHsl = convert.rgb.hsl(_parsedValue.color.r,_parsedValue.color.g,_parsedValue.color.b)
          _newHue = _newHsl[0]
          env.logger.info "_newHsl: " + _newHsl
          @saturation = _newHsl[1]
          @lightness = _newHsl[2]
          env.logger.info "@saturation: " + @saturation + ", @lightness: " + @lightness + ", newHex " + _newHexColor
          @device.getHue()
          .then((hue) =>
            env.logger.info ", _newHue: " + _newHue + ", hue: " + hue # _newHue + ", hue: " + hue  
            unless _newHue == hue
              @device.changeHueTo(_newHue)
              .then(()=>
                @publishState()
              )
          )

      return

    clearDiscovery: () =>
      _topic = @discoveryId + '/' + @device.id + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      @client.publish(_topic, null)

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _config = 
          name: @device.id
          cmd_t: @discoveryId + '/' + @device.id + '/set'
          stat_t: @discoveryId + '/' + @device.id + '/state'
          schema: "json"
          brightness: true
          rgb: true
          #brightness_state_topic: @discoveryId + '/' + @device.id + '/brightness'
          #brightness_command_topic: @discoveryId + '/' + @device.id + '/brightness/set'
          #rgb_state_topic: @discoveryId + '/' + @device.id + '/rgb'
          #rgb_command_topic: @discoveryId + '/' + @device.id + '/rgb/set'
          #state_value_template: "{{ value_json.state }}"
          #brightness_value_template: "{{ value_json.brightness }}"
          #rgb_value_template: "{{ value_json.rgb | join(',') }}"
          #optimistic: false
        _topic = @discoveryId + '/light/' + @device.id + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_config), _options, (err) =>
          if err
            env.logger.error "Error publishing Discovery " + err
        )
        resolve()
      )

    publishState: () =>
      @device.getState()
      .then((state)=>
        if state then _state = "ON" else _state = "OFF"
        @device.getDimlevel()
        .then((dimlevel)=>
          _dimlevel = map(dimlevel,0,100,0,255)
          @device.getHue()
          .then((hue)=>
            _topic = @pimaticId + '/' + @device.id + '/state'
            _rgb = convert.hsl.rgb(hue, @saturation, @lightness)
            env.logger.debug "RGB to publish: " + _rgb
            _payload =
              state: _state
              brightness: _dimlevel
              color: 
                r: _rgb[0]
                g: _rgb[1]
                b: _rgb[2]
            env.logger.debug "Publish colorlight payload: " + JSON.stringify(_payload)
            _options =
              qos : 1
            @client.publish(_topic, JSON.stringify(_payload), _options)
          ).catch((err)=>
            env.logger.error "error getHue " + err
          )
        )
      )

    map = (value, low1, high1, low2, high2) ->
      Math.round(low2 + (high2 - low2) * (value - low1) / (high1 - low1))

    rgbToHue = (r, g, b) ->
      # On the HSV color circle (0..360) the hue value start with red at 0 degrees. We need to convert this
      # to the Milight color circle which has 256 values with red at position 176
      hsv = rgbToHsv(r, g, b)
      (256 + 176 - Math.floor(Number(hsv[0]) / 360.0 * 255.0)) % 256
    rgbToHsv = (r, g, b) ->
      r /= 0xFF
      g /= 0xFF
      b /= 0xFF
      max = Math.max(r, g, b)
      min = Math.min(r, g, b)
      h = undefined
      s = undefined
      v = max
      d = max - min
      s = if max == 0 then 0 else d / max
      if max == min
        h = 0
      else
        switch max
          when r
            h = (g - b) / d + (if g < b then 6 else 0)
          when g
            h = (b - r) / d + 2
          when b
            h = (r - g) / d + 4
        h = Math.round(h * 60)
        s = Math.round(s * 100)
        v = Math.round(v * 100)
      [
        h
        s
        v
      ]

    update: () ->
      env.logger.debug "Update not implemented"

    destroy: ->
      @clearDiscovery()
      @device.removeListener 'state', @stateHandler
      @device.removeListener 'dimlevel', @dimlevelHandler
      @device.removeListener 'hue', @hueHandler
