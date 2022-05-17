// hardhat.config.js
require('hardhat-deploy');
require('hardhat-deploy-ethers');
require('hardhat-gas-reporter');
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-waffle');
require('hardhat-contract-sizer');
require('dotenv').config();

const { PRIVATE_KEY } = process.env;

const ACCOUNTS_PK = [`0x${PRIVATE_KEY}`];

const ACCOUNTS_HD = {
	mnemonic: 'test test test test test test test test test test test junk',
};

task('accounts', 'Prints the list of accounts', async () => {
	const accounts = await ethers.getSigners();

	for (const account of accounts) {
		console.log(account.address);
	}
});

task('blockNumber', 'Prints the current block number', async (_, { ethers }) => {
	await ethers.provider.getBlockNumber().then((blockNumber) => {
		console.log('Current block number: ' + blockNumber);
	});
});

module.exports = {
	solidity: {
		version: '0.6.12',
		settings: {
			optimizer: {
				enabled: true,
				runs: 200,
			},
		},
	},
	networks: {
		mainnet: {
			url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
			accounts: ACCOUNTS_HD,
			chainId: 1,
		},
		goerli: {
			url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
			accounts: ACCOUNTS_HD,
			chainId: 5,
		},
	},
	paths: {
		deploy: 'scripts',
		deployments: 'deployments',
	},
	mocha: {
		timeout: 800000,
		enableTimeouts: false,
	},
	contractSizer: {
		alphaSort: true,
		runOnCompile: true,
		disambiguatePaths: false,
	},
};
