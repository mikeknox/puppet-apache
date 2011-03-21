# Class: apache
#
# This module manages apache
#
# Requires:
#   $contactEmail be set in site manifest
#
# Sample Usage: include apache
#
class apache {
    include apache::params

    package { "$apache::params::apachesvc": 
        alias   => "apachePackage",
    } # package
    
    File {
        before => Service["apacheService"],
    } # File

    if $operatingsystem =~ /SuSE/ {
        file {"$apache::params::basedir/server-tuning.conf":
            content => template("apache/server-tuning.conf-$operatingsystem.erb"),
            require => Package["apachePackage"],
            notify  => Service["apacheService"],
        }
    }

    file {
        # determined by $operatingsystem
        "$apache::params::conffile":
            content => template("apache/httpd.conf-$operatingsystem.erb"),
            require => Package["apachePackage"],
            notify  => Service["apacheService"],
            links   => follow;
        "/etc/sysconfig/$apache::params::apachesvc":
            content => template("apache/sysconfig-${apache::params::apachesvc}.erb"),
            require => Package["apachePackage"],
            notify  => Service["apacheService"];
        # favicon
        "$apache::params::docrootdir/favicon.ico":
            source  => "puppet:///modules/apache/favicon.ico",
            require => Package["apachePackage"];
        # where we stash vhosts across all distros
        "$apache::params::basedir/vhosts.d/":
            mode    => "755",
            ensure  => "directory",
            require => Package["apachePackage"];
        # where module configuration goes
        "$apache::params::basedir/modules.d/":
            mode    => "755",
            ensure  => "directory",
            require => Package["apachePackage"];
        # where configuration goes
        "$apache::params::basedir/conf.d/":
            mode    => "755",
            ensure  => "directory",
            require => Package["apachePackage"];
        "$apache::params::basedir/listen.conf":
            mode    => "755",
            source  => "puppet:///modules/apache/listen.conf";
    } # file

    service { "$apache::params::apachesvc":
        enable     => true,
        ensure     => running,
        hasrestart => true,
        restart    => $apache::params::apachesvc ? {
            /apache2/ => "/usr/sbin/apache2ctl graceful",
            default   => "/usr/sbin/apachectl graceful",
        },
        alias      => "apacheService",
        require    => Package["apachePackage"],
    } # service


    # this define isn't really ment to be called directly - rather by the vhost and module defines below
    define conf_snippet ($ensure = 'present', $location = 'vhosts.d', $content = '', $source = '', $filename = '') {
        $Realname = $filename ? { '' => $name, default => $filename } 
        case $ensure {
            present: {
                case $content {
                    '': {
                        # no cotent means we grab a file
                        $Realsource = $source ? { '' => "puppet:///modules/apache/confs/$Realname.conf", default => $source }
                        file { "$apache::params::basedir/$location/$Realname.conf":
                            ensure  => "present",
                            source  => "$Realsource",
                            require => Package["apachePackage"],
                            notify  => Service["apacheService"],
                        }
                    }

                    default: {
                        # use a template to generate the content
                        file { "$apache::params::basedir/$location/$Realname.conf":
                            ensure  => "present",
                            content => $content,
                            require => Package["apachePackage"],
                            notify  => Service["apacheService"],
                        }
                    }
                } # case $content
            } # present:

            absent: {
                file { "$apache::params::basedir/$location/$Realname.conf":
                    ensure => "absent",
                    notify => Service["apacheService"],
                }
            } # absent:
        } # case $ensure
    } # define conf_snippet

    # Definition: apache::vhost
    #
    # setup a vhost
    #
    # Parameters:   
    #   $ensure  - defaults to 'present'
    #   $content - quoted content or a template
    #   $source  - file to grab with the VirtualHost information
    #   $vhost   - the hostname to use for this vhost, defacts to $name
    #   $docroot - docroot to use, defaults to /srv/www/vhosts/$vhostname/htdocs - this needs to be abstracted out as it is a SuSE path
    #   $cgiroot - cgiroot to use, defaults to /srv/www/vhosts/$vhostname/cgi-bin - this needs to be abstracted out as it is a SuSE path
    #   $contactEmail - contactEmail to use in vhost config
    #   $tempplate - template to use, default is "apache/vhost.conf.erb", not used if $content is defined
    #
    # Actions:
    #   sets up a vhost
    #
    # Requires:
    #   $content our $source must be set
    #
    # Sample Usage:
    # in the mediawiki module you could setup the web portion with the following
    # code, where the mediawiki.conf file contains the <VirtualHost> statements
    #
    #    apache::vhost { "mediawiki":
    #        source => "puppet:///modules/mediawiki/mediawiki.conf",
    #    }
    define vhost ( $ensure = 'present', $content = '', $source = '', $vhost = "",
        $docroot = "", $cgiroot = "",
        $contactEmail = '', $template = '' ) {
        $vhostname = $vhost ? {
            ''      => "$name",
            default => "$vhost",
        }

        $realdocroot = $docroot ? {
            ''      => "$apache::params::baserootdir/vhosts/$vhostname/htdocs",
            default => $docroot,
        }
        $realcgiroot = $cgiroot ? {
            ''      => "$apache::params::baserootdir/vhosts/$vhostname/cgi-bin",
            default => $cgiroot,
        }

        if ($docroot == '' or $cgiroot == '' ) {
            file{["$apache::params::baserootdir/vhosts/$vhostname"]:
                ensure => directory,
                mode   => 0755,
            }
    
        }

        file{["$realdocroot", "$realcgiroot"]:
            ensure => directory,
            mode   => 0755,
        }

        apache::conf_snippet { "vhost-$vhostname":
            ensure   => $ensure,
            content  => $content ? {
                # set content to $content if $content has content
                ''      => $template ? {
                    #if $content doesn't have content check $template
                    '' => $source ? {
                        # Also check $source, if $source doesn't have content then set $comntent to use the default template
                        # if $source has content, leave $content as empty
                        ''      => template("apache/vhost.conf.erb"),
                        default => '',
                    },
                    default => template("$template"),
                },
                default => $content,
            },
            source   => $source,
            location => "vhosts.d",
            filename => $name,
            require  => File["$apache::params::basedir/vhosts.d/"],
        } # apache::conf_shippet
    } # define apache::vhost
    
    # Definition: apache::module
    #
    # setup an apache module - this is used primarily by apache
    # subclasses, such as apache::php, apache::perl, etc
    #       
    # Parameters:    
    #   $ensure  - default to 'present'
    #   $content - quoted content or a template
    #   $source  - file to grab with the VirtualHost information
    #
    # Actions:
    #   sets up an apache module
    #       
    # Requires:
    #   $content our $source must be set
    #       
    # Sample Usage:  
    # this would install the php.conf which includes the LoadModule,
    # AddHandler, AddType and related info that apache needs
    #
    #    apache::module{"php": 
    #        source => "puppet:///modules/apache/php.conf",   
    #    } # apache::module
    define module ( $ensure = 'present', $content = '', $source = '') {
        apache::conf_snippet { "module-$name":
            ensure   => $ensure,
            content  => $content,
            source   => $source,
            location => "conf.d",
            filename => $name,
            require  => File["$apache::params::basedir/conf.d/"],
        } # apache::conf_shippet
    } # define apache::module

    #apache::module { "ldap":
    #    content => "LDAPTrustedGlobalCert CA_BASE64 /etc/pki/tls/certs/ca-ldap.pem",
    #} # apache::module

} # class apache
