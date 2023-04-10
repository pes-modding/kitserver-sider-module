# kitserver-sider-module

This is "Kitserver" - an extension module for Sider 6 and Sider 7.

Full documentation and usage is explained here:
https://evo-web.co.uk/threads/sider-module-kitserver-2020.81143/

### New feature in 1.12

Default behaviour for sleeve badges on "CompKits" (kits for specific competitions)
is different now: Kitserver will no longer hide the badges by moving them
to extreme positions. If you want to go back to previous behaviour, it is easy
to do with the "global config" for Kitserver:

1. create a text file called "config.txt" and put into your Kitserver's content root.
(typically located at "content/kit-server")
1. in that config.txt add:
    ```
    hide_comp_kits_badges = 1
    ```
