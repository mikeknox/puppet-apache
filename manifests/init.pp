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

    # $basedir is the root dir of the httpd config file tree
    $basedir = $operatingsystem ? {
        /SuSE/  => "/etc/apache2",
        default => "/etc/httpd",
    }

    notice "apache:basedir: $basedir"
    $vhostdir = $operatingsystem ? {
        /SuSE/  => "$basedir/conf.d",
        default => "$basedir/vhosts.d",
    }

    $docrootdir = $operatingsystem ? {
        /SuSE/  => "/srv/www/htdocs",
        default => "/var/www/html",
    }

    # $conffile specifies identity of the global httpd config file
    $conffile = $operatingsystem ? {
        /SuSE/   => "$basedir/httpd.conf",
        default  => "$basedir/conf/httpd.conf",
    }

	$apachesvc = $operatingsystem ? {
        /SuSE/  => "apache2",
        default => "httpd",
	}

    package { "$apachesvc": 
        alias   => "apachePackage",
    } # package
    
    File {
        before => Service["apacheService"],
    } # File

    if $operatingsystem =~ /SuSE/ {
        file {"$basedir/server-tuning.conf":
            content => template("apache/server-tuning.conf-$operatingsystem.erb"),
            require => Package["apachePackage"],
            notify  => Service["apacheService"],
        }
    }

    file {
        # determined by $operatingsystem
        "$conffile":
            content => template("apache/httpd.conf-$operatingsystem.erb"),
            require => Package["apachePackage"],
            notify  => Service["apacheService"],
            links   => follow;
        "/etc/sysconfig/$apachesvc":
            content => template("apache/sysconfig-$apachesvc.erb"),
            require => Package["apachePackage"],
            notify  => Service["apacheService"];
        # favicon
        "$docrootdir/favicon.ico":
            source  => "puppet:///modules/apache/favicon.ico",
            require => Package["apachePackage"];
        # where we stash vhosts across all distros
        "$basedir/vhosts.d/":
            mode    => "755",
            ensure  => "directory",
            require => Package["apachePackage"];
        # where module configuration goes
        "$basedir/modules.d/":
            mode    => "755",
            ensure  => "directory",
            require => Package["apachePackage"];
        # where configuration goes
        "$basedir/conf.d/":
            mode    => "755",
            ensure  => "directory",
            require => Package["apachePackage"];
        "$basedir/listen.conf":
            mode    => "755",
            source  => "puppet:///modules/apache/listen.conf";
    } # file

    service { "$apachesvc":
        enable     => true,
        ensure     => running,
        hasrestart => true,
        restart    => $apachesvc ? {
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
                        file { "$apache::basedir/$location/$Realname.conf":
                            ensure  => "present",
                            source  => "$Realsource",
                            require => Package["apachePackage"],
                            notify  => Service["apacheService"],
                        }
                    }

                    default: {
                        # use a template to generate the content
                        file { "$apache::basedir/$location/$Realname.conf":
                            ensure  => "present",
                            content => $content,
                            require => Package["apachePackage"],
                            notify  => Service["apacheService"],
                        }
                    }
                } # case $content
            } # present:

            absent: {
                file { "$apache::basedir/$location/$Realname.conf":
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
            ''      => "/srv/www/vhosts/$vhostname/htdocs",
            default => $docroot,
        }
        $realcgiroot = $cgiroot ? {
            ''      => "/srv/www/vhosts/$vhostname/cgi-bin",
            default => $cgiroot,
        }

        if ($docroot == '' or $cgiroot == '' ) {
            file{["/srv/www/vhosts/$vhostname"]:
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
            require  => File["$apache::basedir/vhosts.d/"],
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
            require  => File["$apache::basedir/conf.d/"],
        } # apache::conf_shippet
    } # define apache::module

    #apache::module { "ldap":
    #    content => "LDAPTrustedGlobalCert CA_BASE64 /etc/pki/tls/certs/ca-ldap.pem",
    #} # apache::module

} # class apache
