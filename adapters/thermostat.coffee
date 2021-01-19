module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = require 'lodash'


  class AssistantThermostatAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix, thermostat) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discovery_prefix = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @hassDeviceFriendlyName = device_prefix + ": " + device.id

      # HASS settings
      @temperatureSetpointItem = "temperatureSetpoint"
      @temperatureSetpointLowItem = "temperatureSetpointLow"
      @temperatureSetpointHighItem = "temperatureSetpointHigh"
      @modeItem = "mode"
      @messageItems = [@modeItem,@temperatureSetpointItem,@temperatureSetpointLowItem,@temperatureSetpointHighItem]

      @device.system = @

      # interim state for connecting pimatic thermosat to hass thermostat
      @thermostats = {}

      @thermostats["DummyHeatingThermostat"] =
        typeModes:
          heating: ["auto","heat"]
        mode:
          heat: "manu"
        program:
          get: "getMode"
          set: "changeModeTo"
          eventName: "mode"
          manual: "manu"
          auto: "auto"
        power: null
        setpoint:
          get: "getTemperatureSetpoint"
          set: "changeTemperatureTo"
          eventName: "temperatureSetpoint"
        setpointLow: null
        setpointHigh: null
        temperature: null

      @thermostats["DummyThermostat"] =
        typeModes:
          heating: ["off","auto","heat"]
          cooling: ["off","auto","cool"]
          heatcool: ["off","heat","auto","cool"]
        mode:
          get: "getMode"
          set: "changeModeTo"
          eventName: "mode"
          heat: "heat"
          auto: "heat"
          cool: "cool"
          heatcool: "heatcool"
          off: "heat"
        program:
          get: "getProgram"
          set: "changeProgramTo"
          eventName: "program"
          manual: "manual"
          auto: "auto"
        power:
          get: "getPower"
          set: "changePowerTo"
          eventName: "power"
          on: true
          off: false
        setpoint:
          get: "getTemperatureSetpoint"
          set: "changeTemperatureTo"
          eventName: "temperatureSetpoint"
        setpointLow:
          get: "getTemperatureSetpointLow"
          set: "changeTemperatureLowTo"
          eventName: "temperatureSetpointLow"
        setpointHigh:
          get: "getTemperatureSetpointHigh"
          set: "changeTemperatureHighTo"
          eventName: "temperatureSetpointHigh"
        temperature:
          get: "getTemperatureRoom"
          set: null
          eventName: "temperatureRoom"

      @thermostats["TadoThermostat"] =
        typeModes:
          heating: ["off","auto","heat"]
        mode: null
        program:
          get: "getProgram"
          set: "changeProgramTo"
          eventName: "program"
          manual: "manual"
          auto: "auto"
        power:
          get: "getPower"
          set: "changePowerTo"
          eventName: "power"
          on: true
          off: false
        setpoint:
          get: "getTemperatureSetpoint"
          set: "changeTemperatureTo"
          eventName: "temperatureSetpoint"
        setpointLow: null
        setpointHigh: null
        temperature:
          get: "getTemperatureRoom"
          set: null
          eventName: "temperatureRoom"

      @thermostat = null

      #env.logger.debug "@device.config.class 1 #{@id} : " + @device.config.class
      if @thermostats[@device.config.class]?
        @thermostat = @thermostats[@device.config.class]
      else 
        @thermostat = @thermostats["DummyHeatingThermostat"]

      @state =
        online: false
        discovery: false
        type: "heating"
        power: true # the on/of button
        mode: "heat"
        modes: @thermostat.typeModes.heating #["off","heat","auto"]
        program: "auto" 
        temperatureAmbient: 20
        humidityAmbient: 50
        temperatureSetpoint: 20
        temperatureSetpointLow: 18
        temperatureSetpointHigh: 22

      #env.logger.debug "@device.config.class 2 #{@id} : " + @device.config.class
      #env.logger.debug "@thermostat #{@id} : " + JSON.stringify(@thermostat,null,2) 

      @modeEventName = @thermostat.mode?.eventName ? null
      @programEventName = @thermostat.program?.eventName ? null
      @powerEventName = @thermostat.power?.eventName ? null
      @setpointEventName = @thermostat.setpoint.eventName ? null
      @setpointLowEventName = @thermostat.setpointLow?.eventName ? null
      @setpointHighEventName = @thermostat.setpointHigh?.eventName ? null
      @temperatureEventName = @thermostat.temperature?.eventName ? null

      @temperatureSensor = if @thermostat.temperature? then true else false
      @powerFunction = if (@thermostat.power?.set? and @thermostat.power?.set? and @thermostat.power?.eventName?) then true else false
      @modeFunction = if (@thermostat.mode?.set? and @thermostat.mode?.set? and @thermostat.mode?.eventName?) then true else false
      @programFunction = if (@thermostat.program?.set? and @thermostat.program?.set? and @thermostat.program?.eventName?) then true else false

      @device.on @setpointEventName, setpointHandler if @setpointEventName?

      env.logger.debug "@powerFunction: " + @powerFunction + ", @modeFunction: " + @modeFunction + ", @programFunction: " + @programFunction

      @device[@thermostat.setpoint.get]() #.getTemperatureSetpoint()
      .then (temp)=>
        @state.temperatureSetpoint = temp
        if @setpointLowEventName?
          @device.on @setpointLowEventName, setpointLowHandler if @setpointLowEventName?
          return @device[@thermostat.setpointLow.get]()
        else
          return null
      .then (tempLow)=>
        if tempLow?
          @state.temperatureSetpointLow = tempLow
        if @setpointHighEventName?
          @device.on @setpointHighEventName, setpointHighHandler if @setpointHighEventName?
          return @device[@thermostat.setpointHigh.get]()
        else
          return null
      .then (tempHigh) =>
        if tempHigh?
          @state.temperatireSetpointHigh = tempHigh
        if @programFunction
          @device.on @programEventName, programHandler if @programEventName?
          return @device[@thermostat.program.get]() #.getProgram()
        else
          return Promise.resolve @thermostat.program.auto
      .then (program)=>
        if program?
          switch program
            when @thermostat.program.auto
              @state.program = @thermostat.program.auto
            else
              @state.program = @thermostat.program.manual
        if @modeFunction
          @device.on @modeEventName, modeHandler if @modeEventName?
          return @device[@thermostat.mode.get]() #.getMode()
        else
          return null
      .then (mode)=>
        env.logger.debug "mode: " + mode
        if mode?
          switch mode
            when @thermostat.mode.heat
              @state.type = "heating" # @thermostat.mode.heat
              @state.mode = "heat" # @thermostat.mode.heat
              @device.on @setpointEventName, setpointHandler
              @state.modes = @thermostat.typeModes.heating ? @modesBasic
              #env.logger.debug "State heat: " + JSON.stringify(@state,null,2) 
            when @thermostat.mode.cool
              @state.type = "cooling" # @thermostat.mode.cool
              @state.mode = "cool" # @thermostat.mode.cool
              @device.on @setpointEventName, setpointHandler
              @state.modes = @thermostat.typeModes.cooling ? @modesBasic
              #env.logger.debug "State cool: " + JSON.stringify(@state,null,2)
            when @thermostat.mode.heatcool
              @state.type = "heatcool" #@thermostat.mode.heat
              @state.mode = "heatcool"
              @state.modes = @thermostat.typeModes.heatcool ? @modesBasic
        if @temperatureSensor
          @device.on @temperatureEventName, temperatureHandler if @temperatureEventName?
          return @device[@thermostat.temperature.get]() #.getTemperatureRoom()
        else
          return null
      .then (temp)=>
        if temp?
          @state.temperatureAmbient = temp
        if @powerFunction
          @device.on @powerEventName, powerHandler if @powerEventName?
          return @device[@thermostat.power.get]() #.getPower()
        else
          return null
      .then (power)=>
        if power?
          @state.power = power
        @publishDiscovery()
        #@setStatus(on)
        #@publishState()
      .finally ()=>
        env.logger.debug "Started ThermostatAdapter #{@id}"
      .catch (err)=>
        env.logger.error "Error init ThermostatAdapter " + err

    modeHandler = (mode) ->
      # device mode changed
      if mode is "heat" #@system.thermostat.mode.heat
        #@system.updateProgram("manual") # @system.thermostat.program.manual)
        @system.updateMode("heat") # @system.thermostat.mode.heat)
      if mode is "cool" # @system.thermostat.mode.cool
        #@system.updateProgram("manual") #@system.thermostat.program.manual)
        @system.updateMode("cool") #@system.thermostat.mode.cool)
      if mode is "heatcool" # @system.thermostat.mode.heatcool
        #@system.updateProgram("manual") # @system.thermostat.program.manual)
        @system.updateMode("heatcool") # @system.thermostat.mode.heatcool)

    getState: () =>
      Promise.resolve(@state)

    powerHandler = (power) ->
      # device mode changed
      @system.updatePower(power)

    programHandler = (program) ->
      # device mode changed
      @system.updateProgram(program)

    setpointHandler = (setpoint) ->
      # device setpoint changed
      @system.updateSetpoint(setpoint)

    setpointLowHandler = (setpointLow) ->
      # device setpoint changed
      @system.updateSetpointLow(setpointLow)

    setpointHighHandler = (setpointHigh) ->
      # device setpoint changed
      @system.updateSetpointHigh(setpointHigh)

    temperatureHandler = (temperature) ->
      # device temperature changed
      @system.updateTemperature(temperature)

    updateMode: (newMode) =>
      unless newMode is @state.mode
        if @modeFunction and newMode in @state.modes
          env.logger.debug "Update '#{@id}' thermostat mode to " + newMode
          switch newMode
            when @thermostat.mode.heat
              @state.mode = "heat"
            when @thermostat.mode.cool
              @state.mode = "cool"
          @publishState()

    updatePower: (newPower) =>
      unless newPower is @state.power
        if @powerFunction
          env.logger.debug "Update '#{@id}' thermostat power to " + newPower
          @state.power = newPower
          #@device[@thermostat.mode.get]()
          #.then (mode)=>
          #  @state.mode = mode
          @publishState()

    updateProgram: (newProgram) =>
      #unless newProgram is @state.program
      if @programFunction
        env.logger.debug "Update '#{@id}' thermostat program to " + newProgram
        switch newProgram
          when @thermostat.program.auto
            @state.program = "auto" # @thermostat.program.auto
            @publishState()
          else
            @state.program = "manual" # @thermostat.program.manual
            #@device[@thermostat.mode.get]()
            #.then (mode)=>
            #  @state.mode = mode
            @publishState()

    updateSetpoint: (newSetpoint) =>
      unless newSetpoint is @state.temperatureSetpoint
        env.logger.debug "Update '#{@id}' setpoint to " + newSetpoint
        #@state.temperatureSetpoint = newSetpoint
        @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
        @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
        @state.temperatureSetpoint = newSetpoint
        @updateProgram("manual")
        #@publishState()

    updateSetpointLow: (newSetpointLow) =>
      unless newSetpointLow is @state.temperatureSetpointLow
        env.logger.debug "Update '#{@id}' setpointLow to " + newSetpointLow
        @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
        @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
        @state.temperatureSetpointLow = newSetpointLow
        @updateProgram("manual")
        #@publishState()

    updateSetpointHigh: (newSetpointHigh) =>
      unless newSetpointHigh is @state.temperatureSetpointHigh
        env.logger.debug "Update '#{@id}' setpointHigh to " + newSetpointHigh
        @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
        @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
        @state.temperatureSetpointHigh = newSetpointHigh
        @updateProgram("manual")
        #@publishState()

    updateTemperature: (newTemperature) =>
      unless newTemperature is @state.temperatureAmbient
        env.logger.debug "Update #{@id} ambiant temperature to " + newTemperature
        @state.temperatureAmbient = newTemperature
        @publishState()

    handleMessage: (packet) =>
      #
      # Messages are in the format of the home-assistant thermostat
      # they use modes like: off, heat, cool, auto
      # this function maps message to current thermostat.function/attribute
      #
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      env.logger.debug "HandleMessage receive for thermostat " + _value + ", packet: " + JSON.stringify(packet)
      for item in @messageItems
        if packet.topic.indexOf(item) >= 0
          env.logger.debug "Topic: " + packet.topic + ", item: " + item + ", value: " + _value
          switch item
            when @modeItem
              if _value.indexOf("auto")>=0 and @programFunction
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.auto) if @programFunction
                #@device[@thermostat.mode.set](@thermostat.mode.auto) if @modeFunction
                #@updateProgram("auto")
                @state.program = "auto"
              else if _value.indexOf("manual")>=0 and @programFunction
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                #@device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updateProgram("manual")
                @state.program = "manual"
              else if _value.indexOf("off")>=0 and @powerFunction
                @device[@thermostat.power.set](@thermostat.power.off) if @powerFunction
                #@device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updatePower(off)
                @state.power = off
              else if _value.indexOf("on")>=0 and @powerFunction
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                #@device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updatePower(on)
                @state.power = on
              else if _value.indexOf("cool")>=0 and @thermostat.mode.cool? #@modeFunction
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                @device[@thermostat.mode.set](@thermostat.mode.cool) if @modeFunction
                #@updateProgram("manual")
                #@updateMode("cool")
                @state.program = "manual"
                @state.mode = "cool"
              else if _value.indexOf("heat")>=0 and @thermostat.mode.heat? #@modeFunction
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                @device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updateProgram("manual")
                #@updateMode("heat")
                @state.program = "manual"
                @state.mode = "heat"
              else
                env.logger.debug "@ModeItem: '#{_value}' is not implemented, value: " + _value
            when @temperatureSetpointItem
              @device[@thermostat.setpoint.set](Number _value)
              .then ()=>
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                #@device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updateSetpoint(Number _value)
                #@updateProgram("manual")
                @state.temperatureSetpoint = Number _value
                @state.program = 'manual'
            when @temperatureSetpointLowItem
              @device[@thermostat.setpointLow.set](Number _value)
              .then ()=>
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                #@device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updateSetpointLow(Number _value)
                #@updateProgram("manual")
                @state.temperatureSetpointLow = Number _value
                @state.program = 'manual'
            when @temperatureSetpointHighItem
              @device[@thermostat.setpointHigh.set](Number _value)
              .then ()=>
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                #@device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                #@updateSetpointHigh(Number _value)
                #@updateProgram("manual")
                @state.temperatureSetpointHigh = Number _value
                @state.program = 'manual'
            else
              env.logger.debug "NOT POSSIBLE!"

    clearDiscovery: () =>
        _topic = @discoveryId + '/climate/' + @hassDeviceId + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null)

    publishDiscovery: () =>
      _modes = @state.modes
      env.logger.debug "Discovery publish hass #{@id} " + JSON.stringify(@state,null,2)
      _config = 
        name: @hassDeviceFriendlyName 
        unique_id: @hassDeviceId
        mode_cmd_t: @discoveryId + '/' + @hassDeviceId+ "/" + @modeItem + "/set"
        mode_stat_t: @discoveryId + '/' + @hassDeviceId+ "/" + @modeItem + "/state"
        temp_cmd_t: @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointItem + "/set"
        temp_stat_t: @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointItem + "/state"
        curr_temp_t: @discoveryId + '/' + @hassDeviceId+ "/temperature/state"
        modes: _modes
        min_temp: "15"
        max_temp: "25"
        temp_step: "0.5"
        availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
        payload_available: "online"
        payload_not_available: "offline"

      if @state.mode is "heatcool"
        _config["temp_hi_cmd_t"] = @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointHighItem + "/set"
        _config["temp_hi_stat_t"] = @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointHighItem + "/state"
        _config["temp_lo_cmd_t"] = @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointLowItem + "/set"
        _config["temp_lo_stat_t"] = @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointLowItem + "/state"

      _topic = @discoveryId + '/climate/' + @hassDeviceId + '/config'
      env.logger.debug "Publish discovery #{@id}, topic: " + _topic + ", config: " + JSON.stringify(_config)

      _options =
        retain: true
        qos: 2
      @client.publish(_topic, JSON.stringify(_config), _options)
  

    publishState: () =>
      env.logger.debug  "publishState hass-thermostat: " + JSON.stringify(@state,null,2)
      if @powerFunction
        env.logger.debug "State: " + JSON.stringify(@state,null,2)
        if @state.power
          if @state.program is "auto"
            _mode = "auto"
          else if @state.mode is "heat"
            _mode = "heat"
          else if @state.mode is "cool"
            _mode = "cool"
          else if @state.mode is "heatcool"
            if @state.temperatureAmbient > @state.temperatureSetpointHigh
              _mode = "cool"
            if @state.temperatureAmbient < @state.temperatureSetpointLow
              _mode = "heat"
          else
            _mode = ""
        else 
          _mode = "off"
      else
        if @state.program is "auto"
          _mode = "auto"
        else if @state.mode is "heat"
          _mode = "heat"
        else if @state.mode is "cool"
          _mode = "cool"
        else if @state.mode is "heatcool"
          _mode = "heat"
          if Number @state.temperatureAmbient > Number @state.temperatureSetpointHigh
            _mode = "cool"
        else
          _mode = "off"

      _options =
        retain: true

      _topic = @discoveryId + '/' + @hassDeviceId + "/" + @modeItem + "/state"
      env.logger.debug "Publish thermostat mode: " + _topic + ", val: " + (String _mode)
      @client.publish(_topic, String _mode, _options)

      switch @state.mode
        when "heat"
          _topic2 = @discoveryId + '/' + @hassDeviceId + "/" + @temperatureSetpointItem + "/state"
          env.logger.debug "Publish thermostat  setpoint: " + _topic2 + ", val: " + @state.temperatureSetpoint
          @client.publish(_topic2, String @state.temperatureSetpoint, _options)
        when "cool"
          _topic2 = @discoveryId + '/' + @hassDeviceId + "/" + @temperatureSetpointItem + "/state"
          env.logger.debug "Publish thermostat  setpoint: " + _topic2 + ", val: " + @state.temperatureSetpoint
          @client.publish(_topic2, String @state.temperatureSetpoint, _options)
        when "heatcool"
          _topic2Low = @discoveryId + '/' + @hassDeviceId + "/" + @temperatureSetpointLowItem + "/state"
          env.logger.debug "Publish thermostat  setpointLow: " + _topic2Low + ", val: " + @state.temperatureSetpointLow
          @client.publish(_topic2Low, String @state.temperatureSetpointLow, _options)
          _topic2High = @discoveryId + '/' + @hassDeviceId + "/" + @temperatureSetpointHighItem + "/state"
          env.logger.debug "Publish thermostat  setpointHigh: " + _topic2High + ", val: " + @state.temperatureSetpointHigh
          @client.publish(_topic2High, String @state.temperatureSetpointHigh, _options)

      if @temperatureSensor
        _topic3 = @discoveryId + '/' + @hassDeviceId + "/temperature/state"
        _temp = @state.temperatureAmbient
        env.logger.debug "Publish thermostat temperature: " + _topic3 + ", val: " + _temp
        @client.publish(_topic3, String _temp, _options)

    update: () ->
      env.logger.debug "Update thermostat not implemented"

    clearAndDestroy: ->
      return new Promise((resolve,reject) =>
        @clearDiscovery()
        @destroy()
        resolve(@id)
      )

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      if online is false
        @state.online = false
        @state.discovered = false
      _options =
        retain: true
        qos: 2
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      env.logger.debug "Publish status: " + _topic + ", status: " + _status
      @client.publish(_topic, String _status, _options)
        
    destroy: ->
      @device.removeListener @setpointEventName, setpointHandler if @setpointEventName?
      @device.removeListener @setpointLowEventName, setpointLowHandler if @setpointLowEventName?
      @device.removeListener @setpointHighEventName, setpointHighHandler if @setpointHighEventName?
      @device.removeListener @modeEventName, modeHandler if @modeFunction and @modeEventName?
      @device.removeListener @powerEventName, powerHandler if @powerFunction if @powerFunction and @powerEventName?
      @device.removeListener @programEventName, programHandler if @programFunction if @programFunction and @programEventName?
      @device.removeListener @temperatureEventName, temperatureHandler if @temperatureSensor and @temperatureEventName?


