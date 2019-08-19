#
# @summary Base profile
#
class openvpn::deploy::service {

  if $facts['service_provider'] == 'systemd' {
    if $openvpn::deploy::client::manage_service {
      service { "openvpn@${name}":
        ensure   => running,
        enable   => true,
        provider => 'systemd',
        require  => File["${etc_directory}/openvpn/${name}.conf"],
      }
    }
  }

  elsif $openvpn::namespecific_rclink {
    file { "/usr/local/etc/rc.d/openvpn_${name}":
      ensure => link,
      target => "${etc_directory}/rc.d/openvpn",
    }

    file { "/etc/rc.conf.d/openvpn_${name}":
      owner   => root,
      group   => 0,
      mode    => '0644',
      content => template('openvpn/etc-rc.d-openvpn.erb'),
    }

    if $openvpn::deploy::client::manage_service {
      service { "openvpn_${name}":
        ensure  => running,
        enable  => true,
        require => [
          File["${etc_directory}/openvpn/${name}.conf"],
          File["/usr/local/etc/rc.d/openvpn_${name}"],
        ],
      }
    }
  }
  else {
    if $openvpn::deploy::client::manage_service {
      service { 'openvpn':
        ensure     => running,
        enable     => true,
        hasrestart => true,
        hasstatus  => true,
      }
    }
  }

}
