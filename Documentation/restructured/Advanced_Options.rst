Advanced Options
=================

This section contains information about advanced settings and options that are available to the application, but may not be typically considered for users.

Account Settings
-----------------

For each connected account, there are sever-specific settings that are available. This may be brought up by selecting More…​ and then choosing the account you wish to edit.

|images/acctsetting|

**General**

-  | Enabled:
   | Whether or not to enable this account. If it is disabled, it will be considered unavailable and offline.

.. Tip::

   Push notifications will not work if the account is disabled!

-  | Change account settings:
   | This screen allows changing of the account password if needed.

**Push Notifications** Tigase Messenger for iOS supports `XEP-0357 Push Notifications <https://xmpp.org/extensions/xep-0357.html>`__ which will receive notifications when a device may be inactive, or the application is closed by the system. Devices must be registered for push notifications and must register them VIA the Tigase XMPP Push Component, enabling push components will register the device you are using.

-  | Enabled:
   | Enables Push notification support. Enabling this will register the device, and enable notifcations.

-  | When in Away/XA/DND state:
   | When enabled, push notifications will be delivered when in Away, Extended away, or Do not disturb statuses which may exist while the device is inactive.

**Message Archiving**

-  | Enabled:
   | Enabling this will allow the device to use the server’s message archive component. This will allow storage and retrieval of messages.

-  | Automatic synchronization:
   | If this is enabled, it will synchronize with the server upon connection, sharing and retrieving message history.

-  | Synchronization:
   | Choose the level of synchronization that the device will retrieve and send to the server.

.. |images/acctsetting| image:: ../images/acctsetting.png

