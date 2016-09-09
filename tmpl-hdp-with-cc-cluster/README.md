# Basic HDP cluster with an additional empty machine intended for CustomerCompass
## Deployment
1. Create a new resource group in a region that allows premium storage. Nowadays, it is available in almost all regions ([Azure Regions Services](https://azure.microsoft.com/en-us/regions/#services) )

2. Start deployment by pushing a button below:

[![Deploy to Azure](http://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

3. Indicate username and password to be able to log into the KAVE. They should be at least **8 characters** long. Note that during the installation the password is stored in a plain text in log files, so make sure to change it after the cluster is up and running.

4. Indicate the names for your storage, premium storage and domain name prefix. These names should be unique and contain only a-z characters and numbers
