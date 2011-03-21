# Class: apache::params
#
# This module manages apache
#
# Requires:
#   $contactEmail be set in site manifest
#
# Sample Usage: include apache::params
#
class apache::params {
    # $basedir is the root dir of the httpd config file tree
    $basedir = $operatingsystem ? {
        /SuSE/  => "/etc/apache2",
        default => "/etc/httpd",
    }

    $vhostdir = $operatingsystem ? {
        /SuSE/  => "$basedir/conf.d",
        default => "$basedir/vhosts.d",
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

    $baserootdir = $operatingsystem ? {
        /SuSE/  => "/srv/www",
        default => "/var/www",
    }

    $docrootdir = $operatingsystem ? {
        /SuSE/  => "$baserootdir/htdocs",
        default => "$baserootdir/html",
    }

}
