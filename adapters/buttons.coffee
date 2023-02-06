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

      #@publishDiscovery()

      @hassDevices = {}
      @activeButton = null
      @keepState = @device.config.enableActiveButton ? true #default is true

      #for _button in device.config.buttons
      #  env.logger.debug "Adding button: " + _button.id
      #  @hassDevices[_button.id] = new buttonManager(@device, _button, @client, @discovery_prefix, device_prefix)

      Promise.each(device.config.buttons, (_button)=>
        @hassDevices[_button.id] = new buttonManager(@device, _button, @client, @discovery_prefix, device_prefix)
      )
      .then ()=>
        @publishDiscovery()
        #@setStatus(on)
        #@publishState()
      ###
      .finally ()=>
        env.logger.debug "Started ButtonsAdapter #{@id}"
      .catch (err)=>
        env.logger.error "Error init ButtonsAdapter " + err
      ###

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
      for i, button of @hassDevices
        @hassDevices[i].publishDiscovery()

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        @hassDevices[i].clearDiscovery()
        @hassDevices[i].destroy()
        resolve(@id)
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
      for i, button of @hassDevices
        @hassDevices[i].setStatus(online)

    destroy: ->
      clearTimeout(@autoStateTimer) if @autoStateTimer?
      clearTimeout(@buttonUpdateTimer) if @buttonUpdateTimer?
      @device.removeListener('button',@buttonHandler)
      for i,button of @hassDevices
        @hassDevices[i].destroy()


  class buttonManager extends events.EventEmitter

    constructor: (device, button, client, discovery_prefix, device_prefix) ->  
      @name = device.name
      @id = device.id
      @device = device
      @button = button

      @client = client
      @pimaticId = discovery_prefix
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + @device.id + "_" + @button.id
      @hassDeviceFriendlyName = device.name + "." + @button.id
      @_getVar = "get" + (@button.id).charAt(0).toUpperCase() + (@button.id).slice(1)

    handleMessage: (buttonId) =>

      env.logger.debug "handlemessage button #{buttonId}"
      @device.buttonPressed(buttonId)

    clearDiscovery: () =>
      _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
      env.logger.debug "Discovery cleared _topic: " + _topic 
      _options =
        qos : 2
        retain: true
      @client.publish(_topic, null, _options)

    publishDiscovery: () =>
      _config = 
        name: @hassDeviceFriendlyName
        unique_id : @hassDeviceId
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
      _topic = @discoveryId + '/' + @hassDeviceId
      env.logger.debug "Button #{@button.id} pushed, sending payload: ON"
      _options =
        qos : 0
      _state = "ON"
      @client.publish(_topic, String _state)

    publishStateOn: () =>
      _topic = @discoveryId + '/' + @hassDeviceId
      env.logger.debug "Button #{@button.id} released, sending payload: ON"
      _state = "ON"
      _options =
        qos : 0
      env.logger.debug "publishStateOn button '#{@button.id}'"
      @client.publish(_topic, String _state)

    publishStateOff: () =>
      _topic = @discoveryId + '/' + @hassDeviceId
      env.logger.debug "Button #{@button.id} released, sending payload: OFF"
      _state = "OFF"
      _options =
        qos : 0
      env.logger.debug "publishStateOff button '#{@button.id}'"
      @client.publish(_topic, String _state)

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      _options =
        qos : 2
        retain: true
      env.logger.debug "Publish status #{@id}: " + _topic + ", status: " + _status
      @client.publish(_topic, String _status, _options)

    destroy: ->
      clearTimeout(@buttonTimer) if @buttonTimer?

  module.exports = ButtonsAdapter
