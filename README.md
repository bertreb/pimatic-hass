# pimatic-hass
Pimatic plugin for making Pimatic devices available in Home Assistant

This plugin is using the mqtt discovery function of Home Assistant (Hass) to automaticaly add pimatic devices. For actionable devices like switch or light the Pimatic devices are synced with Home Assistant. For readonly devices the values are only exposed readable towards Home Assistant.

The communication between Pimatic and Hass is done via mqtt. You need to use a mqtt server that is preferably on your local netwerk.

### Preparing Home Assistant
The whole setup of Home Assistant is out of scope of this plugin. So the starting point is a working Hass system with configurator installed/enabled.
In the configurator you open the file "configurations.yaml" and add the following lines.

```
mqtt:
  broker: <broker ip address>
  username: <broker username>
  password: <broker password>
  port: <broker port>
  discovery: true
  discovery_prefix: hass
```
It's important to use in Hass the same discovery_prefix you are using in the Pimatic plugin. Otherwise the automatic installation of devices will not work.

Now you can add the MQTT integration in Home Assistant.
Goto to the settings menu and select integrations. Pusg the add button (+) and type mqtt.
The MQTT integration will showup and you can select and install it.
Fill in the MQTT server parameters from your mqtt server. Save and exit.

The preparation of Home Assistant is done!

### Preparing Pimatic
Install the Hass plugin. In the plugin you configure the ip address, port, username and password of the mqtt server.
In the field "discovery_prefix" add the same name you used in the mqtt configuration of Hass or leave it empty to use the default ("hass")
If you want you can enable the debug option and read in the logfile log message screen extra debug info.
After succesful installation and configuration of the Hass plugin you can add a Hass device.

### Configuring the Hass device

In the Hass device you can add Pimatic devices by there pimatic-id. No further configuration is needed.
After saving the device config, the connection to Home Assistant is established and per pimatic device that you added in the device config a compatible Hass device is created in Home Assistant. For the VariablesDevices a Hass device is created per variable!

The device type of a Pimatic device determines the Home assistant Device type that is created in Home Assistant device.

Currently the following Pimatic devices are supported.

|Pimatic  |direction | Hass | States
|------------|:--------:|----------|-------------------|
|Switch   | 2-way   | Switch   | on/off
|Presence | 1-way   | Binary   | motion (not) detected
|Light    | 2-way   | Light    | light on/off, brightness
|Contact  | 1-way   | Binary   | opened/closed
|Temp/hum | 1-way   | Binary   | temperature, humidity
|Variables| 1-way	| Variable | variable value

For usage of variables you need to put the variables in a Pimatic VariablesDevice.

### Adding Pimatic devices in the Hass Gui
In Home Assistant the automatic created Pimatic devices can be added as a card via the 'configure UI' option.
Via the add button (+) you can select a device type and search on device name.
The Hass device name is \<hass device type\>.\<pimatic-id\> and can when searching to add a device, also be found under the friendly name \<pimatic-id\>. 

For example adding a pimatic presence sensor with id **presence-livingroom**. In Home Assistant the device gets the following name **binary_sensor.presence-livingroom** or **presence-livingroom** (in the add device search).

For the VariablesDevice the Hass Device is \<hass device type\>.\<Pimatic VariableDevice id\>\_\<Pimatic variable name\>. In the Hass Gui you can group variables on 1 card.

When you remove a Pimatic device from the config, in Home Assistant the card will get yellow and show the message 'entity not available'. You need to remove the card if you want to get rid of this message. If you leave the card in the Gui the entity becomes active again when you add the same Pimatic device again to the config.

### Multiple Pimatic systems

It is possible to connect multiple Pimatic systems to 1 Home Assistant. Per Pimatic system you install the plugin and configure devices as described above. Is Home Assistant all the devices from the different Pimatic sysyem are available. When you use the same pimatic-id's for the same type of device in different Pimatic systems, Hass will add a '\_\<number\>' to the name. In this situation you need to check which hass device belongs to which Pimatic system.

---
The minimum node requirement for this plugin is node v10!
You could backup Pimatic before you are using this plugin!
