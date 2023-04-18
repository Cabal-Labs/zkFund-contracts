import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Provider, utils, Wallet, Contract } from "zksync-web3";
var fs = require('fs');

// ZKETH address on zkSync testnet: 0x0000000000000000000000000000000000000000

export default async function (hre: HardhatRuntimeEnvironment) {
    // The wallet that will deploy the token and the paymaster
    // It is assumed that this wallet already has sufficient funds on zkSync
    // ⚠️ Never commit private keys to file tracking history, or your account could be compromised.
    const provider = new Provider("https://zksync2-testnet.zksync.dev");
    const wallet = new Wallet("", provider);
    
    const deployer = new Deployer(hre, wallet);

    // Deploying the AAFactory contract
    // const factoryArtifact = await deployer.loadArtifact("AAFactory");
    // const aaArtifact = await deployer.loadArtifact("Account");

    // const bytecodeHash = utils.hashBytecode(aaArtifact.bytecode);

    // const factory = await deployer.deploy(
    //    factoryArtifact,
    //    [bytecodeHash],
    //    undefined,
    //    [
    //      aaArtifact.bytecode,
    //    ]
    // );
    // console.log(`AA factory address: ${factory.address}`);
    

    //Deploying the RequestCharities contract
    // const reqCharArtifact = await deployer.loadArtifact("RequestCharities");
    // const reqChar = await deployer.deploy(reqCharArtifact);
    // console.log(`RequestCharities address: ${reqChar.address}`);


    const artifactReq = hre.artifacts.readArtifactSync("RequestCharities");
    const reqChar = new Contract("0xD9ec112662041b5bb456c96A0a4B89246217449E", artifactReq.abi, wallet);

    // Deploying the FundToken contract
    // const fundTokenArtifact = await deployer.loadArtifact("FundToken");
    // const fundToken = await deployer.deploy(fundTokenArtifact, ["FundToken", "FT", 18]);
    // console.log(`FundToken address: ${fundToken.address}`);

    const artifactFund = hre.artifacts.readArtifactSync("FundToken");
    const fundToken = new Contract("0x2708a27129CA654881fb51660494d27cBc7aF82A", artifactFund.abi, wallet);

    // Deploying the CharityRegistry contract
    // const charityRegistryArtifact = await deployer.loadArtifact("CharityRegistry");
    // const charityRegistry = await deployer.deploy(charityRegistryArtifact, [reqChar.address, fundToken.address]);
    // console.log(`CharityRegistry address: ${charityRegistry.address}`);

    const artifactCharity = hre.artifacts.readArtifactSync("CharityRegistry");
    const charityRegistry = new Contract("0x8ffb91036A4EB8250691631c025C297836EEdEf1", artifactCharity.abi, wallet);

    // RequestCharities address: 0xD9ec112662041b5bb456c96A0a4B89246217449E
    // FundToken address: 0x2708a27129CA654881fb51660494d27cBc7aF82A
    // CharityRegistry address: 0x8ffb91036A4EB8250691631c025C297836EEdEf1

    // Conneting Smart Contract to each other.
    try{

        
       await (await reqChar.setCharityRegistry(charityRegistry.address, {
            gasLimit: 10000000,
        })).wait();
        console.log("RequestCharities Contract connected to CharityRegistry");
    }catch(err){
        console.log(err);
    }

    try{
        
        await fundToken.setRegistry(charityRegistry.address, {
            gasLimit: 10000000,
        })
        console.log("FundToken Contract connected to CharityRegistry");
    }catch(err){
        console.log(err);
    }

    console.log("============================== \n ")

	console.log("Adding Test Charity to ValidateCharity contract... Charity Address: 0x330deD2987a65d0B24d7A9379b0F8a66c8302D01 \n");

    try{
        
        await reqChar.initCharity(
            "0x330deD2987a65d0B24d7A9379b0F8a66c8302D01",
            "Test Charity",
            true,
            "bafybeiamgpe4aad4qz4hyad26owkayoh3df7hl6sjlhjzbpjw6hzllxtja",
            {
                gasLimit: 10000000,
            }
        );
    
    }catch(e) {
        console.log(e);
    }

	console.log("============================== \n ")
	

	console.log("Voting for Test Charity...\n ")

	
	await reqChar.vote(1, true,{
        gasLimit: 10000000,
    });

	console.log("============================== \n ")

    console.log("Adding Charity to Charity Resgitry. Charity Address: 0x330deD2987a65d0B24d7A9379b0F8a66c8302D01 \n");


	await reqChar.resolveCharity(1,{
        gasLimit: 10000000,
    });

    console.log("============================== \n ")

    console.log('Set whitelisted token to CharityRegistry contract... \n')

    try{
       
        await reqChar.addTokenToWhitelist("0x0000000000000000000000000000000000000000", {
            gasLimit: 10000000,
        });
    }catch(e){
        console.log(e);
    }
    


    console.log("============================== \n ")

    console.log('Test Charity: 0x330deD2987a65d0B24d7A9379b0F8a66c8302D01, Getting into pool fees \n')

    


    const testCharityWallet = new Wallet("", provider);
    const artifact = hre.artifacts.readArtifactSync("CharityRegistry");
    const charityRegistryForFees = new Contract(charityRegistry.address, artifact.abi, testCharityWallet);




    try{
       
        await charityRegistryForFees.getIntoFeePool(1, ethers.utils.parseEther("0.03"), {
            gasLimit: 10000000,
        });
        

    }catch(e){
        console.log(e);
    }


    console.log("============================== \n ")
    
	
    console.log("Deployment complete! CharityRegistry address:", charityRegistry.address, " \n ValidateCharities address:", reqChar.address, "\n FundToken address:", fundToken.address, "\n AAFactory address:", );
    const jsonData = JSON.stringify({
		"ValidateCharities": reqChar.address,
		"CharityRegistry": charityRegistry.address,
        "FundToken": fundToken.address,
        //"AAFactory": factory.address
	})
	//Writing addresses to file
	fs.exists('ContractAddresses.json', function(exists: any) {
		if (exists) {
			//Edditing file
			fs.readFile('ContractAddresses.json', 'utf8', function readFileCallback(err: any, data: any){
				if (err){
					console.log(err);
				}
				else {
					var obj = JSON.parse(data);
					obj.RequestCharities = reqChar.address;
					obj.CharityRegistry = charityRegistry.address;
                    obj.FundToken = fundToken.address;
                    //obj.AAFactory = factory.address;
					var json = JSON.stringify(obj);
					fs.writeFile('ContractAddresses.json', json, 'utf8', function(err: any) {
						if (err) {
							console.log(err);
						}
					});
				}	
			});
		}else{
			fs.writeFile('ContractAddresses.json', jsonData, 'utf8', function(err: any) {
				if (err) {
					console.log(err);
				}
			});
		}
		
	});
	

}
