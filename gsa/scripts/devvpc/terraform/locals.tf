locals {
  # EFS Tree names
  efstags = {
    Terraform  = "true"
    Team = "Ops"
    ResourceRole="Conexus EFS File System"
    Service="DBFolders"
    ResourceClass="FileStorage"
    Application = "Conexus"
  }
  efschroottag = {
    Name = "Magnolia"
    ResourceRole = "Conexus SFTP Data"
  }
  efsquarantinetag = {
    Name = "Banyan"
    ResourceRole = "Conexus SFTP reject"
  }
  efsdatabasetag = {
    Name = "Maple"
    ResourceRole = "Conexus SFTP Database"
  }
  efsattachmentstag = {
    Name = "Alder"
    ResourceRole = "Conexus Order attachments"
  }
  efsreportstag = {
    Name = "Baobab"
    ResourceRole = "Conexus UI Reports"
  }
  # Motorcycles for AdminTools
  kmstags = {
    Terraform = "true"
    Team = "Ops"
    ResourceRole="Conexus kms key for secrets manager"
    Service="KMS"
    ResourceClass="AdminTool"
    Application = "Conexus"
  }
  kmschroottag= {
    Name="Aero"
  }
  kmsdatabasetag = {
    Name="Benelli"
  }

}
