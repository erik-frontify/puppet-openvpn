# @summary This define creates the openvpn ca and ssl certificates
#
# @param country Country to be used for the SSL certificate
# @param province Province to be used for the SSL certificate
# @param city City to be used for the SSL certificate
# @param organization Organization to be used for the SSL certificate
# @param email Email address to be used for the SSL certificate
# @param common_name Common name to be used for the SSL certificate
# @param group User to drop privileges to after startup
# @param ssl_key_size Length of SSL keys (in bits) generated by this module.
# @param key_expire The number of days to certify the server certificate for
# @param ca_expire The number of days to certify the CA certificate for
# @param key_name Value for name_default variable in openssl.cnf and KEY_NAME in vars
# @param key_ou Value for organizationalUnitName_default variable in openssl.cnf and KEY_OU in vars
# @param key_cn Value for commonName_default variable in openssl.cnf and KEY_CN in vars
# @param tls_auth Determins if a tls key is generated
# @param tls_static_key Determins if a tls key is generated
# @example
#   openvpn::ca {
#     'my_user':
#       server      => 'contractors',
#       remote_host => 'vpn.mycompany.com'
#    }
#
define openvpn::ca (
  String $country,
  String $province,
  String $city,
  String $organization,
  String $email,
  String $common_name     = 'server',
  Optional[String] $group = undef,
  Integer $ssl_key_size   = 2048,
  Integer $ca_expire      = 3650,
  Integer $key_expire     = 3650,
  Integer $crl_days       = 30,
  String $key_cn          = '',
  String $key_name        = '',
  String $key_ou          = '',
  Boolean $tls_auth       = false,
  Boolean $tls_static_key = false,
) {

  if $tls_auth {
    warning('Parameter $tls_auth is deprecated. Use $tls_static_key instead.')
  }

  include openvpn
  $group_to_set = $group ? {
    undef   => $openvpn::group,
    default => $group
  }

  File {
    group => $group_to_set,
  }

  $etc_directory = $openvpn::etc_directory

  ensure_resource('file', "${etc_directory}/openvpn/${name}", {
    ensure => directory,
    mode   => '0750'
  })

  file { "${etc_directory}/openvpn/${name}/easy-rsa" :
    ensure             => directory,
    recurse            => true,
    links              => 'follow',
    source_permissions => 'use',
    group              => 0,
    source             => "file:${openvpn::easyrsa_source}",
    require            => File["${etc_directory}/openvpn/${name}"],
  }

  file { "${etc_directory}/openvpn/${name}/easy-rsa/revoked":
    ensure  => directory,
    mode    => '0750',
    recurse => true,
    require => File["${etc_directory}/openvpn/${name}/easy-rsa"],
  }

  case $openvpn::easyrsa_version {
    '2.0': {
      file { "${etc_directory}/openvpn/${name}/easy-rsa/vars":
        ensure  => file,
        mode    => '0550',
        content => template('openvpn/vars.erb'),
        require => File["${etc_directory}/openvpn/${name}/easy-rsa"],
      }

      if $openvpn::link_openssl_cnf {
        File["${etc_directory}/openvpn/${name}/easy-rsa/openssl.cnf"] {
          ensure => link,
          target => "${etc_directory}/openvpn/${name}/easy-rsa/openssl-1.0.0.cnf",
          before => Exec["initca ${name}"],
        }
      }

      exec { "generate dh param ${name}":
        command  => '. ./vars && ./clean-all && ./build-dh',
        timeout  => 20000,
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/dh${ssl_key_size}.pem",
        provider => 'shell',
        require  => File["${etc_directory}/openvpn/${name}/easy-rsa/vars"],
      }

      exec { "initca ${name}":
        command  => '. ./vars && ./pkitool --initca',
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/ca.key",
        provider => 'shell',
        require  => Exec["generate dh param ${name}"],
      }

      exec { "generate server cert ${name}":
        command  => ". ./vars && ./pkitool --server ${common_name}",
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/${common_name}.key",
        provider => 'shell',
        require  => Exec["initca ${name}"],
      }

      exec { "create crl.pem on ${name}":
        command  => ". ./vars && KEY_CN='' KEY_OU='' KEY_NAME='' KEY_ALTNAMES='' openssl ca -gencrl -out ${etc_directory}/openvpn/${name}/crl.pem -config ${etc_directory}/openvpn/${name}/easy-rsa/openssl.cnf",
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/crl.pem",
        provider => 'shell',
        require  => Exec["generate server cert ${name}"],
      }

    }
    '3.0': {
      file { "${etc_directory}/openvpn/${name}/easy-rsa/vars":
        ensure  => file,
        mode    => '0550',
        content => epp('openvpn/vars-30.epp',
          {
            'etc_directory'  => $etc_directory,
            'openvpn_server' => $name,
            'ssl_key_size'   => $ssl_key_size,
            'ca_expire'      => $ca_expire,
            'key_expire'     => $key_expire,
            'crl_days'       => $crl_days,
            'country'        => $country,
            'province'       => $province,
            'city'           => $city,
            'organization'   => $organization,
            'email'          => $email,
            'key_cn'         => $key_cn,
            'key_ou'         => $key_ou,
          }
        ),
        require => File["${etc_directory}/openvpn/${name}/easy-rsa"],
      }

      # looks like changes with version easy-rsa-3.0.3-1.el7 need the revoked directy under easy-rsa/keys/revoked/certs_by_serial
      file { "${etc_directory}/openvpn/${name}/easy-rsa/revoked/certs_by_serial":
        ensure  => directory,
        mode    => '0750',
        recurse => true,
        require => File["${etc_directory}/openvpn/${name}/easy-rsa/revoked"],
      }
      file { "${etc_directory}/openvpn/${name}/easy-rsa/keys/revoked":
        ensure  => link,
        target  => "${etc_directory}/openvpn/${name}/easy-rsa/revoked",
        require => File["${etc_directory}/openvpn/${name}/easy-rsa/revoked"],
      }
      if $openvpn::link_openssl_cnf {
        File["${etc_directory}/openvpn/${name}/easy-rsa/openssl.cnf"] {
          ensure => link,
          target => "${etc_directory}/openvpn/${name}/easy-rsa/openssl-1.0.cnf",
          before => Exec["initca ${name}"],
        }
      }

      exec { "initca ${name}":
        command  => './easyrsa --batch init-pki && ./easyrsa --batch build-ca nopass',
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/ca.crt",
        provider => 'shell',
        require  => File["${etc_directory}/openvpn/${name}/easy-rsa/vars"],
      }

      exec { "generate dh param ${name}":
        command  => './easyrsa --batch gen-dh',
        timeout  => 20000,
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/dh.pem",
        provider => 'shell',
        require  => Exec["generate server cert ${name}"],
      }

      exec { "generate server cert ${name}":
        command  => "./easyrsa build-server-full ${common_name} nopass",
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/private/${common_name}.key",
        provider => 'shell',
        require  => Exec["initca ${name}"],
      }

      file { "${etc_directory}/openvpn/${name}/easy-rsa/keys/ca.crt":
        mode    => '0640',
        require => Exec["initca ${name}"],
      }

      exec { "create crl.pem on ${name}":
        command  => ". ./vars && EASYRSA_REQ_CN='' EASYRSA_REQ_OU='' openssl ca -gencrl -out ${etc_directory}/openvpn/${name}/crl.pem -config ${etc_directory}/openvpn/${name}/easy-rsa/openssl.cnf",
        cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
        creates  => "${etc_directory}/openvpn/${name}/crl.pem",
        group    =>  $group_to_set,
        provider => 'shell',
        require  => Exec["generate server cert ${name}"],
      }

    }
    default: {
      fail("unexepected value for EasyRSA version, got '${openvpn::easyrsa_version}', expect 2.0 or 3.0.")
    }
  }

  file { "${etc_directory}/openvpn/${name}/easy-rsa/openssl.cnf":
    require => File["${etc_directory}/openvpn/${name}/easy-rsa"],
  }

  file { "${etc_directory}/openvpn/${name}/keys":
    ensure  => link,
    target  => "${etc_directory}/openvpn/${name}/easy-rsa/keys",
    mode    => '0640',
    require => File["${etc_directory}/openvpn/${name}/easy-rsa"],
  }

  file { "${etc_directory}/openvpn/${name}/crl.pem":
    mode    => '0640',
    require => Exec["create crl.pem on ${name}"],
  }

  if $tls_static_key {
    exec { "generate tls key for ${name}":
      command  => 'openvpn --genkey --secret keys/ta.key',
      cwd      => "${etc_directory}/openvpn/${name}/easy-rsa",
      creates  => "${etc_directory}/openvpn/${name}/easy-rsa/keys/ta.key",
      provider => 'shell',
      require  => Exec["generate server cert ${name}"],
    }
  }

  file { "${etc_directory}/openvpn/${name}/easy-rsa/keys/crl.pem":
    ensure  => link,
    target  => "${etc_directory}/openvpn/${name}/crl.pem",
    require => Exec["create crl.pem on ${name}"],
  }
}
