pub_cache_cleaner
=================

Version: 0.0.5

Utility to clean the pub cache from obsolete packages.

This utility may be considered as safest way of removing unused packages from the packages cache. It are safer than you remove some packages manually.

This means that you may install for the your experiments any packages into your system and after a time when these packages you will no longer need you may easy remove them from cache.

The algorithm that used in this utility can described in short words as the following sequence.

1. Scan entire home directory and find all Dart applications.
2. During this scanning process collect information about all linked to cache packages.
3. After collection of the all required information in the all found applications computed difference between packages located in cache and the outside referenced packages in cache.
4. Packages that exists in cache but never referenced in home directory considered as unreferenced.
5. All packages without references considered as an unused packages because they not referensed nowhere outside.

Running this utilty without parameters only show information about unused packages.

IMPORTANT:

Do not use this tool if you are using a Windows system, and you are not sure that your applications are located only in your home directory.
