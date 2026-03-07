
JEUTOOL
=======

by Andrew Apted, 2018.


About
-----

Pronounced: *Zhur-Tool*

JeuTool is a command-line tool for packing and unpacking WAD files.
The concept is similar to DeuTex, but JeuTool works quite differently.
For example, it does not require a "wadinfo" file to describe the
contents of a WAD to build, instead the lumps are just found by
scanning the filesystem.

The name is a combination of the French word *jeu*, which means "game",
and the English word *tool*, which means a "tool", a piece of software
which has some utility.


Website
-------

https://gitlab.com/andwj/jeutool


Documentation
-------------

Please read the fine [User Manual](MANUAL.md).


Binary Packages
---------------

https://gitlab.com/andwj/jeutool/tags/v0.8.0


Legalese
--------

JeuTool is Copyright &copy; 2018 Andrew Apted.

JeuTool is Free Software, under the terms of the GNU General Public
License, version 3 or (at your option) any later version.
See the [LICENSE.txt](LICENSE.txt) file for the complete text.

JeuTool comes with NO WARRANTY of any kind, express or implied.
Please read the license for full details.


Compiling
---------

JeuTool is written in pure Go, and the dependencies are quite
minimal (and are also pure Go).  Hence CGO is not required,
making compiling and even cross-compiling fairly easy.

To build and install the binary:
```
go get -v gitlab.com/andwj/jeutool
```


Contact
-------

You can report bugs via the Issues page on the GitLab project
page, at the following link:

https://gitlab.com/andwj/jeutool/issues

I prefer not to be contacted by email, thanks.

