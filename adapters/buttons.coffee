module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = require("lodash")

  class ButtonsAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discovery_prefix = discovery_prefix
      @hassDevices = {}
      @activeButton = null
      @keepState = @device.config.enableActiveButton ? true #default is true

      for _button in device.config.buttons
        env.logger.debug "Adding button: " + _button.id
        @hassDevices[_button.id] = new buttonManager(@device, _button, @client, @discovery_prefix, device_prefix)

      @buttonHandler = (buttonId) =>
        env.logger.debug "Button handler, button '#{buttonId}' pressed, with activeButton = " + @activeButton + ", keepState: " + @keepState
        unless buttonId? then return #or @activeButton isnt buttonId then return
        if @keepState
          if @activeButton?
            @hassDevices[@activeButton].publishStateOff() 
          @hassDevices[buttonId].publishStateOn()
          @activeButton = buttonId
        else
          @hassDevices[buttonId].publishStateOn()
          @activeButton = buttonId
          #if @activeButton?
          #  #env.logger.debug "Switching current button(Hass switch) off"
          #  #@hassDevices[@activeButton].publishStateOff() 
          env.logger.debug "Switching pressed button(Hass switch) on"
          #else
          #  @hassDevices[buttonId].publishStateOn()
          #  @activeButton = buttonId
          setTimeout( @autoStateTimer = () =>
            @hassDevices[buttonId].publishStateOff()
          ,6000)


      @device.on 'button', @buttonHandler

    publishState: () =>
      @device.getButton()
      .then (activeButton)=>
        for i, button of @hassDevices
          if i is activeButton
            @hassDevices[i].publishStateOn()
          else
            @hassDevices[i].publishStateOff()

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        publishDiscoveries = []
        for i, button of @hassDevices
          publishDiscoveries.push button.publishDiscovery()
        Promise.all(publishDiscoveries)
        .then ()=>
          resolve @id
      )

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        clears =[]
        destroys =[]
        for i, button of @hassDevices
          clears.push @hassDevices[i].clearDiscovery()
          destroys.push @hassDevices[i].destroy()
        Promise.all(clears)
        .then ()=>
          return Promise.all(destroys)
        .then ()=>
          resolve()
        .catch (err) =>
          env.logger.debug "Error clear and destroy "
      )
    
    clearDiscovery: () =>
      for i, button of @hassDevices
        @hassDevices[i].clearDiscovery()

    handleMessage: (packet) =>
      #_items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload
      #env.logger.debug "Buttons message received " + _value
      _button = _.find(@hassDevices, (hassD) => (packet.topic).indexOf(hassD.button.id) >= 0 )
      if _button?
        #check if lastPressedButton equals _button.id
        #env.logger.debug "_button found with id: " + _button.button.id + ", activeButton: " +  @activeButton

        #if @activeButton isnt _button.button.id
        if _value.indexOf("ON") >= 0
          _button.handleMessage(_button.button.id)
        else
          @activeButton = null


    update: (deviceNew) =>
      addHassDevices = []
      removeHassDevices = []
      for _button,i in deviceNew.config.buttons
        if !_.find(@hassDevices, (hassD) => hassD.button.id == _button.id )
          addHassDevices.push deviceNew.config.buttons[i]
      env.logger.debug "Tot hier"
      removeHassDevices = _.differenceWith(@device.config.buttons, deviceNew.config.buttons, _.isEqual)
      for removeDevice in removeHassDevices
        env.logger.debug "Removing button " + removeDevice.name
        @hassDevices[removeDevice.id].clearDiscovery()
        .then ()=>
          @hassDevices[removeDevice.id].destroy()
          delete @hassDevices[removeDevice.name]

      @device = deviceNew
      for _button in addHassDevices
        env.logger.debug "Adding button" + _button.id
        @hassDevices[_button.id] = new buttonManager(deviceNew, _button, @client, @discovery_prefix, device_prefix)
        @hassDevices[_button.id].publishDiscovery()
        .then((_i) =>
          setTimeout( ()=>
            @hassDevices[_i].publishStateOff()
            @device.on 'button', @buttonHandler
          , 5000)
        ).catch((err) =>
        )

    setStatus: (online) =>
      for i, _button of @hassDevices
        @hassDevices[i].setStatus(online)

    destroy: ->
      return new Promise((resolve,reject) =>
        clearTimeout(@autoStateTimer) if @autoStateTimer?
        clearTimeout(@buttonUpdateTimer) if @buttonUpdateTimer?
        @device.removeListener('button',@buttonHandler)
        for i,button of @hassDevices
          @hassDevices[i].destroy()
        resolve()
      )


  class buttonManager extends events.EventEmitter

    constructor: (device, button, client, discovery_prefix, device_prefix) ->  
      @name = device.name
      @id = device.id
      @device = device
      @button = button

      #@unit = @device.attributes[@button.id]?.unit ? ""
      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + @device.id + "_" + @button.id
      @hassDeviceFriendlyName = device_prefix + ": " + device.id + "." + @button.id
      @_getVar = "get" + (@button.id).charAt(0).toUpperCase() + (@button.id).slice(1)
      #env.logger.debug "_getVar: " + @_getVar

      ###
      @_buttonId = @button.id
      @_handlerName = @button.id + "Handler"
      @buttonHandler = (buttonId) =>
        if buttonId is @button.id
          env.logger.debug "Button '#{@button.id}' change: " + buttonId
          @publishState()

      #@device.on 'button', @buttonHandler
      #env.logger.debug "Button constructor " + @name + ", handlerName: " + @_handlerName
      ###

    handleMessage: (buttonId) =>

      env.logger.debug "handlemessage button #{buttonId}"
      @device.buttonPressed(buttonId)

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, (err) =>
          if err
            env.logger.error "Error publishing Discovery Variable  " + err
            reject()
          resolve()
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _config = 
          name: @hassDeviceFriendlyName
          unique_id : @hassDeviceId
          cmd_t: @discoveryId + '/' + @hassDeviceId + '/set'
          stat_t: @discoveryId + '/' + @hassDeviceId
          availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
          payload_available: "online"
          payload_not_available: "offline"
        _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_config),  (err) =>
          if err
            env.logger.error "Error publishing Discovery Button  " + err
            reject()
          resolve(@id)
        )
      )

    publishState: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/' + @hassDeviceId
        env.logger.debug "Button #{@button.id} pushed, sending payload: ON"
        _options =
          qos : 1
        _state = "ON"
        @client.publish(_topic, String _state, (err) =>
          if err
            env.logger.error "Error publishing state Button  " + err
            reject()
          resolve()
        )
        ###
        setTimeout( @buttonTimer = ()=>
          env.logger.debug "Button #{@button.id} released, sending payload: OFF"
          _state = "OFF"
          @client.publish(_topic, String _state, _options, (err) =>
            if err
              env.logger.error "Error publishing state Button  " + err
              reject()
            resolve()
          )
        , 6000)
        ###
      )

    publishStateOn: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/' + @hassDeviceId
        env.logger.debug "Button #{@button.id} released, sending payload: ON"
        _state = "ON"
        _options =
          qos : 0
        env.logger.debug "publishStateOn button '#{@button.id}'"
        @client.publish(_topic, String _state, (err) =>
          if err
            env.logger.error "Error publishing state Button  " + err
            reject()
          resolve()
        )
      )

    publishStateOff: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/' + @hassDeviceId
        env.logger.debug "Button #{@button.id} released, sending payload: OFF"
        _state = "OFF"
        _options =
          qos : 0
        env.logger.debug "publishStateOff button '#{@button.id}'"
        @client.publish(_topic, String _state, (err) =>
          if err
            env.logger.error "Error publishing state Button  " + err
            reject()
          resolve()
        )
      )

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      _options =
        qos : 0
      env.logger.debug "Publish status: " + _topic + ", _status: " + _status
      @client.publish(_topic, String _status) #, _options)

    destroy: ->
      #@device.removeListener @_variableName, @buttonHandler
      clearTimeout(@buttonTimer)
      #@clearDiscovery()

  module.exports = ButtonsAdapter
