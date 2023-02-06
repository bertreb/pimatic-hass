module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class CoverAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      #@pimaticId = pimaticId
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @device_prefix = device_prefix
      @hassDeviceFriendlyName = device.name

      @publishDiscovery()

      @rollingtime = 20000

      @covers = {}

      @covers["DummyShutter"] =
        modes: ["position"]
        position:
          get: "getPosition"
          set: "moveToPosition"
          eventName: "position"
          closed: "down"
          closing: "down"
          open: "up"
          opening: "up"
          stopped: "stopped"
        tilt: null
        power: null

      if @covers[@device.config.class]?
        @cover = @covers[@device.config.class]
      else 
        @cover = @covers["DummyShutter"]

      @_coverPosition = @cover.position?.down ? "down"
      @_coverTilt = @cover.tilt?.open ? "open"
      @_coverPower = @cover.power?.on ? true

      @state =
        power: @cover.power?.on ? true
        position: @cover.position?.closed ? "closed"
        tilt: @cover.tilt?.closed ? null 

      @positionEventName = @cover.position?.eventName ? null
      @tiltEventName = @cover.tilt?.eventName ? null
      @powerEventName = @cover.power?.eventName ? null

      @positionFunction = if @cover.position? then true else false
      @powerFunction = if @cover.power? then true else false
      @tiltFunction = if @cover.tilt? then true else false

      env.logger.debug "@powerFunction: " + @powerFunction + ", @tiltFunction: " + @tiltFunction + ", @positionFunction: " + @positionFunction

      @device[@cover.position.get]()
      .then (position)=>
        @state.position = @handlePosition(position)
        env.logger.debug "Cover position init: " + @state.position
        if @tiltFunction
          @device.on @tiltEventName, @tiltHandler if @tiltEventName?
          return @device[@cover.tilt.get]() 
        else
          return null
      .then (tilt)=>
        if tilt?
          @state.tilt = @handleTilt(tilt)
        if @powerFunction
          @device.on @powerEventName, @powerHandler if @powerEventName?
          return @device[@cover.power.get]()
        else
          return null
      .then (power)=>
        if power?
          @state.power = power
        #@publishDiscovery()
        #@setStatus(on)
        #@publishState()
      .finally ()=>
        env.logger.debug "Started CoverAdapter #{@id}"
      .catch (err)=>
        env.logger.error "Error init CoverAdapter " + err

      @device.on @positionEventName, @positionHandler if @positionEventName?

    positionHandler: (position) =>
      env.logger.debug "Position change cover: " + position + ", @_coverPosition: " + @_coverPosition
      if position is @cover.position.open and (@_coverPosition isnt @cover.position.open) 
        @state.position = "opening"
        @publishState()
        @rollingTimer = setTimeout(()=>
          @state.position = "open"
          @_coverPosition = @cover.position.open
          @publishState()
        , @rollingtime)
        # set timer
      if position is @cover.position.closed and (@_coverPosition isnt @cover.position.closed)
        @state.position = "closing"
        @publishState()
        @rollingTimer = setTimeout(()=>
          @state.position = "closed"
          @_coverPosition = @cover.position.closed
          @publishState()
        , @rollingtime)
        # set timer
      @_coverPosition = position

    tiltHandler: (tilt) =>
      env.logger.debug "Tilt change cover: " + tilt
      @state.tilt = tilt
    
    powerHandler: (power) =>
      env.logger.debug "Power change cover: " + power
      @state.power = power

    handlePosition: (position) =>
      # cover positio in and Hass position out
      switch position
        when @cover.position.closed
          return "closed"
        when @cover.position.closing
          return "closing"
        when @cover.position.open
          return "open"
        when @cover.position.opening
          return "opening"
        when @cover.position.stopped
          return "stopped"

    handleTilt: (tilt) =>
      return "open"

    handlePower: (power) =>
      return on

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      env.logger.debug "Cover payload " + _value + ", @_coverPosition " + @_coverPosition
      if (String _value) is "CLOSE" and @_coverPosition isnt @cover.position.closed
        @state.position = "closing"
        @publishState()
        @rollingTimer = setTimeout(()=>
          @device.moveToPosition("down")
          @state.position = "closed"
          @_coverPosition = @cover.position.closed
          @publishState()
        , @rollingtime)

      else if (String _value) is "OPEN" and @_coverPosition isnt @cover.position.open
        @state.position = "opening"
        @publishState()
        @rollingTimer = setTimeout(()=>
          @device.moveToPosition("up")
          @state.position = "open"
          @_coverPosition = @cover.position.open
          @publishState()
        , @rollingtime)

      else if (String _value) is "STOP"
        @device.moveToPosition("stopped")
        @state.position = "stopped"
        @_coverPosition = @cover.position.stopped
        @publishState()

      else if (String _value) is "CLOSE" and @_coverPosition is @cover.position.down
        @device.moveToPosition("down")
        @state.position = "closed"
        @_coverPosition = @cover.position.closed
        @publishState()

      else
        env.logger.debug "Message for Cover not found, resetting to closed cover"
        @state.position = "closing"
        @publishState()
        @rollingTimer = setTimeout(()=>
          @device.moveToPosition("down")
          @state.position = "closed"
          @_coverPosition = @cover.position.closed
          @publishState()
        , @rollingtime)


    clearDiscovery: () =>
        _topic = @discoveryId + '/cover/' + @hassDeviceId + '/config'
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
        stat_t: @discoveryId + '/' + @hassDeviceId + '/state'
        state_open: "open"
        state_opening: "opening"
        state_closed: "closed"
        state_closing: "closing"
        availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
        payload_available: "online"
        payload_not_available: "offline"

      _topic = @discoveryId + '/cover/' + @hassDeviceId + '/config'
      env.logger.debug "Publish discovery #{@id}, topic: " + _topic + ", config: " + JSON.stringify(_config)
      _options =
        qos : 2
        retain: true
      @client.publish(_topic, JSON.stringify(_config), _options)

    publishState: () =>
      # publish position only
      _position = @state.position

      _topic = @discoveryId + '/' + @hassDeviceId + '/state'
      _options =
        qos : 0
      env.logger.debug "Publish cover #{@id}: " + _topic + ", position: " + _position
      @client.publish(_topic, String _position) #, _options)
      Promise.resolve()

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
      env.logger.debug "Publish status #{@id}: " + _topic + ", status: " + _status
      @client.publish(_topic, String _status, _options)

    destroy: ->
      @device.removeListener 'position', @positionHandler if @positionHandler?
      @device.removeListener 'tilt', @tiltHandler if @tiltHandler?
      @device.removeListener 'power', @powerHandler if @powerHandler?
      clearTimeout(@rollingTimer) if @rollingTimer?
