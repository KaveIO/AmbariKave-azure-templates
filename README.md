# Ambarikave-azure-templates: Public KAVE on Azure templates

In this repo we contain publishable azure deployments of the AmbariKave. These deployments can be run via their *Deploy to Azure* buttons or via the azure-cli.

Supported templates currently are: 

 - HDP with CI stack.

## Overview

This repository contains the source code necessary for the automated deployment of [KAVE](http://kave.io) on [Azure](https://azure.microsoft.com/). The environments are provisionable via a deploy button; visualization is one click away too: 

![deploy](http://azuredeploy.net/deploybutton.png)
![visualize](http://armviz.io/visualizebutton.png)

## For developers

For creating a good template we rever to the description by [Microsoft](https://github.com/Azure/azure-quickstart-templates/blob/master/README.md) though there are some additional steps involved for us. A developer may be interested in starting the process from the command line, for better control and debug. This can be done by using the [azure_setup.ps1](/automation/local_scripts/azure_setup.ps1) PowerShell script. The [Azure CLI](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/) must be installed first.

## Useful links

 * [Azure REST API specs](https://github.com/Azure/azure-rest-api-specs) - this is very useful to read the definition of the latest API version for an entity and write compliant JSON requests for it
 
 * [Azure specs library](https://msdn.microsoft.com/en-us/library/azure/mt163564.aspx) - find here the detailed documentation of the API together with readymade REST calls by version
 
 * [Azure quickstart templates](https://github.com/Azure/azure-quickstart-templates) - this are very useful to learn how to deploy idiomatic clusters, together with the usage of a particular API version of the components it offers
 
 * [Atlas of the Azure platform](http://azureplatform.azurewebsites.net)

