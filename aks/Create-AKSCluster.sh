#!/bin/bash
SUBSCRIPTION="your-subscription-name"
RSG_NAME="aks-release-demo"
LOCATION="australiaeast"

az account set --subscription $SUBSCRIPTION

az group create --name $RSG_NAME --location $LOCATION

az aks create --name "prod-cluster" --resource-group $RSG_NAME --location $LOCATION --node-count 1 --enable-addons monitoring --generate-ssh-keys

az aks create --name "stage-cluster" --resource-group $RSG_NAME --location $LOCATION --node-count 1 --enable-addons monitoring --generate-ssh-keys

az aks create --name "dev-cluster" --resource-group $RSG_NAME --location $LOCATION --node-count 1 --enable-addons monitoring --generate-ssh-keys

