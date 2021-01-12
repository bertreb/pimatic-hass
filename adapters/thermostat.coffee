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
      @modeItem = "mode"
      @messageItems = [@temperatureSetpointItem,@modeItem]

      # interim state for connecting pimatc thermosat to hass thermostat
      @state =
        power: true # the on/of button
        mode: "heat"
        program: "auto" 
        temperatureAmbient: 20
        humidityAmbient: 50
        temperatureSetpoint: 20

      @thermostats = {}

      @thermostats["DummyHeatingThermostat"] =
        modes: ["heat","auto"]
        mode:
          get: "getMode"
          set: "changeModeTo"
          eventName: "mode"
          heat: "manu"
          auto: "auto"
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
        temperature: null

      @thermostats["DummyThermostat"] =
        modes: ["off","heat","auto"]
        mode:
          get: "getMode"
          set: "changeModeTo"
          eventName: "mode"
          heat: "manual"
          auto: "auto"
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
        temperature:
          get: "getTemperatureRoom"
          set: null
          eventName: "temperatureRoom"

      if @thermostats[@device.config.class]?
        @thermostat = @thermostats[@device.config.class]
      else 
        @thermostat = @thermostats["DummyHeatingThermostat"]

      @modeEventName = @thermostat.mode?.eventName ? null
      @programEventName = @thermostat.program?.eventName ? null
      @powerEventName = @thermostat.power?.eventName ? null
      @setpointEventName = @thermostat.setpoint.eventName ? null
      @temperatureEventName = @thermostat.temperature?.eventName ? null

      @temperatureSensor = if @thermostat.temperature? then true else false
      @powerFunction = if @thermostat.power? then true else false
      @modeFunction = if @thermostat.mode? then true else false
      @programFunction = if @thermostat.program? then true else false

      @device.system = @
      @device.on @setpointEventName, setpointHandler

      @modes = @thermostat.modes

      env.logger.debug "@powerFunction: " + @powerFunction + ", @modeFunction: " + @modeFunction + ", @programFunction: " + @programFunction

      @device[@thermostat.setpoint.get]() #.getTemperatureSetpoint()
      .then (temp)=>
        @state.temperatureSetpoint = temp
        if @programFunction
          @device.on @programEventName, programHandler if @programEventName?
          return @device[@thermostat.program.get]() #.getProgram()
        else
          return Promise.resolve "auto"
      .then (program)=>
        if program?
          switch program
            when "auto"
              @state.program = "auto"
              @state.mode = "auto"
            else
              @state.program = "manual"
              @state.mode = "heat"
        if @modeFunction
          @device.on @modeEventName, modeHandler if @modeEventName?
          return @device[@thermostat.mode.get]() #.getMode()
        else
          return null
      .then (mode)=>
        if mode?
          switch mode 
            when "heat"
              @state.mode = "heat"
              @state.program = "manual"              
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
      .finally ()=>
        env.logger.debug "State: " + JSON.stringify(@state,null,2)
      .catch (err)=>
        env.logger.debug "Error init thermostat " + err

    modeHandler = (mode) ->
      # device mode changed
      if mode is 'heat'
        @system.updateProgram("manual")
        @system.updateMode("heat")

    powerHandler = (power) ->
      # device mode changed
      @system.updatePower(power)

    programHandler = (program) ->
      # device mode changed
      @system.updateProgram(program)

    setpointHandler = (setpoint) ->
      # device setpoint changed
      @system.updateSetpoint(setpoint)

    temperatureHandler = (temperature) ->
      # device temperature changed
      @system.updateTemperature(temperature)

    updateMode: (newMode) =>
      unless newMode is @state.program
        env.logger.debug "Update thermostat mode to " + newMode
        @state.mode = newMode
        @publishState()

    updatePower: (newPower) =>
      #unless newPower is @state.power
      env.logger.debug "Update thermostat power to " + newPower
      @state.power = newPower
      @publishState()

    updateProgram: (newProgram) =>
      #unless newMode is @state.thermostatMode
      if @programFunction
        env.logger.debug "Update thermostat program to " + newProgram
        switch newProgram
          when "auto"
            @state.program = "auto"
          else
            @state.program = "manual"
            @state.mode = "heat"
        @publishState()

    updateSetpoint: (newSetpoint) =>
      unless newSetpoint is @state.temperatureSetpoint
        env.logger.debug "Update setpoint to " + newSetpoint
        @state.temperatureSetpoint = newSetpoint
        @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
        @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
        @updateProgram("manual")
        #@publishState()

    updateTemperature: (newTemperature) =>
      #unless newTemperature is @state.temperatureAmbient
      env.logger.debug "Update ambiant temperature to " + newTemperature
      @state.temperatureAmbient = newTemperature
      @publishState()

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      #env.logger.debug "HandleMessage receive for thermostat " + _value + ", packet: " + JSON.stringify(packet)
      for item in @messageItems
        #env.logger.debug "Topic: " + packet.topic + ", item: " + item + ", value: " + _value
        if packet.topic.indexOf(item) >= 0
          switch item
            when @modeItem
              if _value.indexOf("auto")>=0
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.auto) if @programFunction
                @device[@thermostat.mode.set](@thermostat.mode.auto) if @modeFunction
                @updateProgram("auto")
              else if _value.indexOf("off")>=0
                @device[@thermostat.power.set](@thermostat.power.off) if @powerFunction
                @device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                @updateMode("off")
              else
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                @device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                @updateProgram("manual")
                @updateMode("heat")
            when @temperatureSetpointItem
              @device[@thermostat.setpoint.set](Number _value)
              .then ()=>
                @device[@thermostat.power.set](@thermostat.power.on) if @powerFunction
                @device[@thermostat.program.set](@thermostat.program.manual) if @programFunction
                @device[@thermostat.mode.set](@thermostat.mode.heat) if @modeFunction
                @updateProgram("manual")
            else
              env.logger.debug "NOT POSSIBLE!"

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/climate/' + @hassDeviceId + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, (err)=>
          if err
            env.logger.error "Error clearing Discovery thermostat " + err
            reject()
          resolve(@id)
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _config = 
          name: @hassDeviceFriendlyName 
          unique_id: @hassDeviceId
          mode_cmd_t: @discoveryId + '/' + @hassDeviceId+ "/" + @modeItem + "/set"
          mode_stat_t: @discoveryId + '/' + @hassDeviceId+ "/" + @modeItem + "/state"
          temp_cmd_t: @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointItem + "/set"
          temp_stat_t: @discoveryId + '/' + @hassDeviceId+ "/" + @temperatureSetpointItem + "/state"
          curr_temp_t: @discoveryId + '/' + @hassDeviceId+ "/temperature/state"
          modes: @modes
          min_temp: "15"
          max_temp: "25"
          temp_step: "0.5"
    
        _topic = @discoveryId + '/climate/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_config)

        @client.publish(_topic, JSON.stringify(_config), (err) =>
          if err
            env.logger.error "Error publishing Discovery " + err
            reject()
          resolve(@id)
        )
      )

    publishState: () =>

      if @powerFunction
        #env.logger.debug "POWER: @state.power = " + @state.power
        if @state.power
          if @state.program is "auto"
            _mode = "auto"
          else
            _mode = "heat"
        else 
          _mode = "off"
      else
        if @state.program is "auto"
          _mode = "auto"
        else if @state.mode is "heat"
          _mode = "heat"
        else 
          _mode = "off"

      _topic2 = @discoveryId + '/' + @hassDeviceId + "/" + @temperatureSetpointItem + "/state"
      #env.logger.debug "Publish thermostat  setpoint: " + _topic2 + ", val: " + @state.temperatureSetpoint
      @client.publish(_topic2, String @state.temperatureSetpoint)

      if @temperatureSensor
        _topic3 = @discoveryId + '/' + @hassDeviceId + "/temperature/state"
        _temp = @state.temperatureAmbient
        #env.logger.debug "Publish thermostat  temperature: " + _topic3 + ", val: " + _temp
        @client.publish(_topic3, String _temp)

      _topic = @discoveryId + '/' + @hassDeviceId + "/" + @modeItem + "/state"
      #env.logger.debug "Publish thermostat mode: " + _topic + ", val: " + (String _mode)
      @client.publish(_topic, String _mode)


    update: () ->
      env.logger.debug "Update thermostat not implemented"

    clearAndDestroy: ->
      return new Promise((resolve,reject) =>
        @clearDiscovery()
        .then () =>
          return @destroy()
        .then ()=>
          resolve()
        .catch (err) =>
          env.logger.debug "Error clear and destroy Thermostat"
      )

    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener @setpointEventName, setpointHandler
        @device.removeListener @modeEventName, modeHandler if @modeFunction and @modeEventName?
        @device.removeListener @powerEventName, powerHandler if @powerFunction if @powerFunction and @powerEventName?
        @device.removeListener @programEventName, programHandler if @programFunction if @programFunction and @programEventName?
        @device.removeListener @temperatureEventName, temperatureHandler if @temperatureSensor and @temperatureEventName?
      )


