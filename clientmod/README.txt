Thank you to the people helping with the particle:
  FancyNight [U:1:160000225] - sprite work
  sigmarune [U:1:154407981] - particle effect

Sadly particle systems are one of the few systems that for whatever reason
require a manifest, that can not easily be extended or post loaded by the
server in any awy, for particles to be usable ingame. This means that I can
not really use the particle as it can not be exptected from players to install
a mod for a single particle effect. And no the server can't even download the
vpk in the right directory, source engine has no "server mod-packs" like
minecraft.

If you run a modded server network like creators and you do want to use the
particle, you can:
- repack the particle into your mod, or use the vpk provided
 -> don't forget to fix up the particles_manifest.txt if you have any more
    custom .pcf files
- change the particle in the plugins .sp
 -> there's a block pretty much at the top that sais
    #define PVP_PARTICLE "mark_for_death"
    change that to
    #define PVP_PARTICLE "pvpoptin_indicator"
- recompile the plugin
 -> if you don't want to manage dependencies, you can just run the build tool
    sps.bat on windows or ./sps on linux (currently nees some extra setup for
    github dependencies to download)
- load the plugin on the server and give your players the vpk
