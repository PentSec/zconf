# zconf.tcl - v0.7.2-dev
# ZNC user management system
# --------------------------
# REQUIREMENTS:
# - eggdrop 1.8
# - ZNC admin account
if {[catch {source scripts/zconf-settings.tcl} err]} {
	putlog "Error: Could not load 'scripts/zconf-settings.tcl' file.";
}
putlog "zConf loaded";
if {![file exists "userdir"]} {
	file mkdir "userdir"
	file mkdir "userdir/settings"
	file mkdir "userdir/admin"
}
namespace eval zconf {
	namespace eval bind {
		# zConf Public Commands
		bind pub - ${zconf::settings::pubtrig}request zconf::proc::request
		bind pub - ${zconf::settings::pubtrig}approve zconf::proc::approve
		bind pub - ${zconf::settings::pubtrig}zhelp zconf::help::pub
		bind pub - ${zconf::settings::pubtrig}version zconf::proc::version
		bind pub - ${zconf::settings::pubtrig}info zconf::proc::info
		bind pub - ${zconf::settings::pubtrig}status zconf::proc::status
		bind pub - ${zconf::settings::pubtrig}admins zconf::proc::admins
		# zConf Admin Commands
		bind msg - adduser zconf::proc::admin::msg::adduser
		bind msg - deluser zconf::proc::admin::msg::deluser
		bind msg - regset zconf::proc::admin::msg::regset
		bind pub - ${zconf::settings::admtrig}chk zconf::proc::check
		bind pub - ${zconf::settings::pubtrig}userban zconf::proc::userban
		bind pub - ${zconf::settings::pubtrig}banuser zconf::proc::userban
		# Return from *controlpanel
		bind msg - Error: zconf::proc::zncresponce:error
		bind msg - User zconf::proc::zncresponce:good
		# public help section
		bind msg - zhelp zconf::help::main
		# DCC commands
		bind dcc m znc zconf::proc::znc
		bind dcc m nsauth zconf::proc::nsauth
		bind dcc m addadmin zconf::proc::admin::dccadmadd
	}
	namespace eval proc {
		proc request {nick uhost hand chan text} {
			if {[lindex [split $text] 0] == ""} { putserv "PRIVMSG $chan :Error - Please specify username."; return }
			set regdb "userdir/settings/regset"
			set udb "userdir/$nick"
			set bdb "userdir/$nick.ban"
			set ndb "userdir/$nick.un"
			set nickdb "userdir/[lindex [split $text] 0].nick"
			set regstat [zconf::util::read_db $regdb]
			if {$regstat == "public"} {
				if {[file exists $udb]} { putserv "PRIVMSG $chan :Error - You already have an account"; return }
				if {[file exists $bdb]} { putserv "PRIVMSG $chan :Error - You are banned: [zconf::util::read_db $bdb]"; return }
				set authnick "userdir/$nick.auth"
				zconf::util::write_db $ndb [lindex [split $text] 0]
				zconf::util::write_db $nickdb $nick
				zconf::util::write_db $authnick [zconf::util::randpass 5]
				putserv "NOTICE $nick :Your approval code is [zconf::util::read_db $authnick] | type @approve <code> to finish"
				return
			}
			if {$regstat == "off"} { putserv "PRIVMSG $chan :Error - Public registration is disabled."; return }
		}
		proc approve {nick uhost hand chan text} {
			set v1 [lindex [split $text] 0]
			set udb "userdir/$nick"
			if {![llength [split $v1]]} { putserv "PRIVMSG $chan Error - Please include your auth code"; return }
			if {[file exists $udb]} { putserv "PRIVMSG $chan :Error - You already have an account"; return }
			set authnick "userdir/$nick.auth"
			set propcode [zconf::util::read_db $authnick]
			if {![string match $v1 $propcode]} { putserv "PRIVMSG $chan :Error - Inavlid auth code"; return }
			if {[string match $v1 $propcode]} {
				putserv "PRIVMSG $chan :Your ZNC password will be /notice'd to you."
				set passwd [zconf::util::randpass 15]
				set ndb "userdir/$nick.un"
				putserv "PRIVMSG *controlpanel :AddUser [zconf::util::read_db $ndb] $passwd"
				putserv "NOTICE $nick :$passwd"
			}
		}
		proc version {nick uhost hand chan text} {
			putserv "PRIVMSG $chan :zconf.tcl - zConf v[getVersion] ZNC Account request system"
		}
		proc info {nick uhost hand chan text} {
			putserv "PRIVMSG $chan :zConf is currently running."
			putserv "PRIVMSG $chan :Access zConf ZNC at [getURL]"
		}
		proc status {nick uhost hand chan text} {
			set hostname [exec hostname]
			set commandfound 0;
			set fp [open "| uptime"]
			set data [read $fp]
			if {[catch {close $fp} err]} {
			putserv "PRIVMSG $chan :Error getting status..."
			} else {
			set output [split $data "\n"]
			foreach line $output {
				putserv "PRIVMSG $chan :${line}"
				}
			}
		}
		proc admins {nick uhost hand chan text} { putserv "PRIVMSG $chan :[zconf::util::listadmin $chan]"}
		proc userban {nick uhost hand chan arg} {
			if {[isAdmin $nick] == "0"} { putserv "PRIVMSG $chan :Error - only admins can run that command."; return }
			set txt [split $arg]
			set v1 [string tolower [lindex $txt 0]]
			set msg [join [lrange $txt 1 end]]
			set ndb "userdir/$v1.nick"
			set bnick [zconf::util::read_db $ndb]
			set udb "userdir/$v1.ban"
			if {![llength [split $v1]]} { putserv "PRIVMSG $chan :Please specify a username and a reason"; return }
			if {![llength [split $msg]]} { putserv "PRIVMSG $chan :Please specify a username and a reason"; return }
			if {![file exists $bnick]} { putserv "PRIVMSG $chan :Error - User does not exist"; return }
			if {[lindex [split [zconf::util::read_db $udb]] 0] == "Banned"} { putserv "PRIVMSG $chan :Error - User already banned"; return }
			zconf::util::write_db $udb "Banned for $msg"
			putserv "PRIVMSG $chan :Banning user $v1 for $msg"
			putserv "PRIVMSG *controlpanel :DelUser $v1"
		}
		proc znc {hand idx text} {
			putserv "PASS :zconf/rueo:[zncPass]"
		}
		proc nsauth {hand idx text} {
			putserv "PRIVMSG NickServ :IDENTIFY [getPass]"
		}
		proc check {nick uhost hand chan text} {
			putserv "PRIVMSG $chan :Admin Check - [isAdmin $nick]";
		}
		proc zncresponce:error {nick uhost hand arg} {
			putlog "zConf: responce from $nick - $arg"
			#if {$nick != "*controlpanel"} { return }
			global zconf::settings::zchan
			set txt [split $arg]
			set msg [lrange $txt 0 end]
			putserv "PRIVMSG $zconf::settings::zchan :$msg"
		}
		proc zncresponce:good {nick uhost hand arg} {
			putlog "zConf: responce from $nick - $arg"
			set txt [split $arg]
			set msg [lrange $txt 0 end]
			putserv "PRIVMSG [getChan] :$msg"
		}
		proc getPass {} {
			global zconf::settings::pass
			return $zconf::settings:pass
		}
		proc zncPass {} {
			global zconf::settings::zncpass
			return $zconf::settings::zncpass
		}
		proc getChan {} {
			global zconf::settings::zchan
			return $zconf::settings::zchan
		}
		proc getURL {} {
			global zconf::settings::url
			return $zconf::settings::url
		}
		proc getVersion {} {
			global zconf::settings::version
			return $zconf::settings::version
		}
		proc isAdmin {nick} {
			if {[file exists "userdir/admin/$nick"]} { return "1" } else { return "0" }
		}
		namespace eval admin {
			proc isAdmin {nick} {
				if {[file exists "userdir/admin/$nick"]} { return "1" } else { return "0" }
			}
			proc dccadmadd {hand idx text} {
				if {[file exists "userdir/admin/$text"]} { putdcc $idx "zConf - Error - $text is already a zConf admin"; return }
				if {![file exists "userdir/admin/$text"]} {
					set adb "userdir/admin/$text"
					zconf::util::write_db $adb "1"
					if {[file exists $adb]} { putdcc $idx "zConf: Successfully added $text ad a zConf admin"; return }
					if {![file exists $adb]} { putdcc $idx "zConf: Error adding $text - please try again"; return }
				}
			}
			proc admin {nick uhost hand chan text} {
				if {[isAdmin $nick] == "0"} { putserv "PRIVMSG $chan :Error - only admins can run that command."; return }
				set v1 [lindex [split $text] 0]
				set v2 [lindex [split $text] 1]
				set v3 [lindex [split $text] 2]
				set v4 [lindex [split $text] 3]
				set v5 [lindex [split $text] 4]
				if {$v1 == "add"} {
					if {[file exists "userdir/admin/$v2"]} { putserv "PRIVMSG $chan :Error - $v2 is already a zConf admin"; return }
					if {![file exists "userdir/admin/$v2"]} {
						set adb "userdir/admin/$v2"
						zconf::util::write_db $adb "1"
						if {[file exists $adb]} { putserv "PRIVMSG $chan :zConf: Successfully added $v2 ad a zConf admin"; return }
						if {![file exists $adb]} { putserv "PRIVMSG $chan :zConf: Error adding $v2 - please try again"; return }
					}
				}
				if {$v1 == "list"} { putserv "PRIVMSG $chan :[zconf::util::listadmin $chan]"; return }
			}
			namespace eval msg {
				proc adduser {nick uhost hand text} {
					if {[isAdmin $nick] == "0"} { putserv "NOTICE $nick :Error - only admins can run that command."; return }
					set v1 [lindex [split $text] 0]
					if {![llength [split $v1]]} { putserv "NOTICE $nick :Please specify a username to create"; return }
					set udb "userdir/$v2"
					set passwd [zconf::util::randpass 15]
					putserv "PRIVMSG *controlpanel :AddUser $v1 $passwd"
					putserv "NOTICE $nick :ZNC passwordv for $v1 - $passwd"
				}
				proc deluser {nick uhost hand text} {
					if {[isAdmin $nick] == "0"} { putserv "NOTICE $nick :Error - only admins can run that command."; return }
					set v1 [lindex [split $text] 0]
					if {![llength [split $v1]]} { putserv "NOTICE $nick :Please specify a username to create"; return }
					set udb "userdir/$v2"
					if {![file exists $udb]} { putserv "NOTICE $nick :Error - $v1 does not exist."; return }
					putserv "PRIVMSG *controlpanel deluser $v1";
					putserv "NOTICE $nick :User \003$v1\003 deleted"
				}
				proc regset {nick uhost hand chan text} {
					if {[zconf::proc::isAdmin $nick] == "0"} { putserv "PRIVMSG $chan :Error - only admins can run that command."; return }
					set v1 [lindex [split $text] 0]
					if {![llength [split $v1]]} {
						putserv "PRIVMSG $chan :Error - please specify option."
						putlog "zConf \$ \[COMMAND LOG\] :admin: regset - no args"
						return
					}
					if {$v1 == "public"} {
						set regdb "userdir/settings/regset"
						zconf::util::write_db $regdb "public"
						putserv "PRIVMSG $chan :Registration set to Public"
						putlog "zConf \$ \[COMMAND LOG\] :admin: regset - args: public"
						return
					}
					if {$v1 == "off"} {
						set regdb "userdir/settings/regset"
						zconf::util::write_db $regdb "off"
						putserv "PRIVMSG $chan :Registration set to Off. | until reenabled, zConf will not accept new registrations."
						putserv "zConf \$ \[COMMAND LOG\] :admin: regset - args: "
					}
				}
			}
		}
	}
	namespace eval help {
		proc main {nick uhost hand text} {
			set v1 [lindex [split $text] 0]
			set v2 [lindex [split $text] 1]
			set v3 [lindex [split $text] 2]
			set v4 [lindex [split $text] 3]
			set v5 [lindex [split $text] 4]
			set v6 [lindex [split $text] 5]
			putserv "NOTICE $nick : \037/!\\\037 - The help system is currently being made."
			if {![llength [split $v1]]} { putserv "NOTICE $nick :Error - No input given."}
			if {$v1 == "commands"} {
				putserv "NOTICE $nick :Help article for \036$v1\036"
				putserv "NOTICE $nick :Current public commands are:"
				putserv "NOTICE $nick :version request approve info zhelp status"
				if {[zconf::proc::admin::isAdmin $nick] == "1"} {
					putserv "NOTICE $nick :Administration Commands are:"
					putserv "NOTICE $nick :adduser deluser regset"
				}
				putserv "NOTICE $nick :to find out more, use /msg [getNick] zhelp \002command\002"
				return
			}
			if {$v1 == "version"} { putserv "NOTICE $nick :displays current version to the channel."; return }
			if {$v1 == "request"} { putserv "NOTICE $nick :submit a znc account request"; return }
			if {$v1 == "approve"} { putserv "NOTICE $nick :submit your approval code for a znc account"; return }
			if {$v1 == "info"} { putserv "NOTICE $nick :see info on how to connect to the znc"; return }
			if {$v1 == "status"} { putserv "NOTICE $chan :See znc server load status"; return }
			if {$v1 == "zhelp"} { putserv "NOTICE $nick :view the basic help info"; return}
			if {$v1 == "adduser"} {
				if {[zconf::proc::admin::isAdmin $nick] == "0"} { return }
				putserv "NOTICE $nick :USAGE - /msg [getNick] adduser \002username\002"
				putserv "NOTICE $nick :FUNCTION - adds a user to the db | restricted to admins"
				return
			}
			if {$v1 == "deluser"} {
				if {[zconf::proc::admin::isAdmin $nick] == "0"} { return }
				putserv "NOTICE $nick :USAGE - /msg [getNick] deluser \002username\002"
				putserv "NOTICE $nick :FUNCTION - deletes a user from the db | restricted to admins"
				return
			}
			if {$v1 == "regset"} {
				if {[zconf::proc::admin::isAdmin $nick] == "0"} { return }
				putserv "NOTICE $nick :USAGE /msg [getNick] regset \002\[public|off\]\002"
				putserv "NOTICE $nick :FUNCTION - set zConf registration status | restricted to admins"
			}
		}
		proc pub {nick uhost hand chan text} {
			putserv "PRIVMSG $chan :For help, use /msg [getNick] zhelp"
		}
		proc getNick {} {
			global botnick
			return $botnick
		}
	}
	namespace eval util {
		# write to *.db files
		proc write_db { w_db w_info } {
			set fs_write [open $w_db w]
			puts $fs_write "$w_info"
			close $fs_write
		}
		# read from *.db files
		proc read_db { r_db } {
			set fs_open [open $r_db r]
			gets $fs_open db_out
			close $fs_open
			return $db_out
		}
		# create *.db files, servers names files
		proc create_db { bdb db_info } {
			if {[file exists $bdb] == 0} {
				set crtdb [open $bdb a+]
				puts $crtdb "$db_info"
				close $crtdb
			}
		}
		proc randpass {length {chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"}} {
		set range [expr {[string length $chars]-1}]

		set txt ""
		for {set i 0} {$i < $length} {incr i} {
			set pos [expr {int(rand()*$range)}]
			append txt [string range $chars $pos $pos]
			}
		return $txt
		}
		proc listadmin {chan} {
			putserv "PRIVMSG $chan :- Current zConf admin listing -"
			set commandfound 0;
			set fp [open "| ls /home/rvzm/zconf/userdir/admin/"]
			set data [read $fp]
			if {[catch {close $fp} err]} {
			putserv "PRIVMSG $chan :Error listing admins..."
			} else {
			set output [split $data "\n"]
			putserv "PRIVMSG $chan :@output"
			}
		}
	}
}
