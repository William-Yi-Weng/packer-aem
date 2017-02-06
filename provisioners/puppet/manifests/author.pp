class author (
  $aem_quickstart_source,
  $aem_license_source,
  $aem_healthcheck_version,
  $aem_base           = '/opt',
  $aem_jvm_mem_opts   = '-Xmx4096m',
  $aem_port           = '4502',
  $aem_sample_content = false
) {

  stage { 'test':
    require => Stage['main']
  }

  file { "${aem_base}/aem":
    ensure => directory,
    mode   => '0775',
    owner  => 'aem',
    group  => 'aem',
  }

  file { "${aem_base}/aem/author":
    ensure  => directory,
    mode    => '0775',
    owner   => 'aem',
    group   => 'aem',
    require => File["${aem_base}/aem"],
  }

  # Retrieve the cq-quickstart jar and move into aem/author directory
  archive { "${aem_base}/aem/author/aem-author-${aem_port}.jar":
    ensure  => present,
    source  => $aem_quickstart_source,
    cleanup => false,
    require => File["${aem_base}/aem/author"],
  } ->
    file { "${aem_base}/aem/author/aem-author-${aem_port}.jar":
      ensure  => file,
      mode    => '0775',
      owner   => 'aem',
      group   => 'aem',
      require => File["${aem_base}/aem/author"],
    }

  # Retrieve the license file and move into aem/author directory
  archive { "${aem_base}/aem/author/license.properties":
    ensure  => present,
    source  => "${aem_license_source}",
    cleanup => false,
    require => File["${aem_base}/aem/author"],
  } ->
    file { "${aem_base}/aem/author/license.properties":
      ensure => file,
      mode   => '0440',
      owner  => 'aem',
      group  => 'aem',
    }

  aem::instance { 'aem':
    source         => "${aem_base}/aem/author/aem-author-${aem_port}.jar",
    home           => "${aem_base}/aem/author",
    type           => 'author',
    port           => $aem_port,
    sample_content => $aem_sample_content,
    jvm_mem_opts   => $aem_jvm_mem_opts,
    jvm_opts       => '-XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintTenuringDistribution -XX:+PrintGCApplicationStoppedTime -XX:+HeapDumpOnOutOfMemoryError',
    status         => 'running',
  }

  file { '/etc/puppetlabs/puppet/aem.yaml':
    ensure  => file,
    content => epp('/tmp/templates/aem.yaml.epp', { 'port' => $aem_port }),
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
  }

  # Confirm AEM starts up and the login page is ready.
  aem_aem { 'Wait until login page is ready':
    ensure  => login_page_is_ready,
    require => [Aem::Instance['aem'], File['/etc/puppetlabs/puppet/aem.yaml']],
  }

  class { 'aem_resources::author_remove_default_agents':
    require => [Aem_aem['Wait until login page is ready']],
  }

  class { 'aem_resources::create_system_users':
    require => [Aem_aem['Wait until login page is ready']],
  }

  aem_package { 'Install AEM Healthcheck Content Package':
    ensure    => present,
    name      => 'aem-healthcheck-content',
    group     => 'shinesolutions',
    version   => "${aem_healthcheck_version}",
    path      => "${aem_base}/aem",
    replicate => false,
    activate  => false,
    force     => true,
    require   => [Aem_aem['Wait until login page is ready']],
  }

  file { "${aem_base}/aem/aem-healthcheck-content-${aem_healthcheck_version}.zip":
    ensure  => absent,
    require => Aem_package['Install AEM Healthcheck Content Package'],
  }

  # Ensure login page is still ready after all provisioning steps and before stopping AEM.
  aem_aem { 'Ensure login page is ready':
    ensure  => login_page_is_ready,
    require => [
      Class['aem_resources::author_remove_default_agents'],
      Class['aem_resources::create_system_users'],
      File["${aem_base}/aem/aem-healthcheck-content-${aem_healthcheck_version}.zip"],
    ]
  } ->
    exec { 'service aem-aem stop':
      cwd  => '/tmp',
      path => ['/usr/bin', '/usr/sbin'],
    }

  class { 'serverspec':
    stage             => 'test',
    component         => 'author',
    staging_directory => '/tmp/packer-puppet-masterless-1',
    tries             => 5,
    try_sleep         => 3,
  }

}

include author
