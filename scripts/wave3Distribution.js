usePlugin('@nomiclabs/buidler-ethers');
const fs = require('fs');
const path = require('path');
const BN = require('ethers').BigNumber;

let configPath;

const uniswapRouter = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
let boostTokenAddress;
let gasPrice = new BN.from(20).mul(new BN.from(10).pow(new BN.from(9)));
let starttime;
let duration;
let uniswapLP;
let multisig;
let tokens;
let internalPoolBoostAmount = new BN.from('15000').mul(new BN.from('10').pow(new BN.from('18')));
let rewardsPoolBoostAmount = new BN.from('3750').mul(new BN.from('10').pow(new BN.from('18')));
let rewardsPool;

task('wave3Deploy', 'deploy wave 3 reward pools').setAction(async () => {
  network = await ethers.provider.getNetwork();
  const [deployer] = await ethers.getSigners();
  let deployerAddress = await deployer.getAddress();
  let RewardsPool;

  configPath = path.join(__dirname, './mainnet_settings.json');
  readParams(JSON.parse(fs.readFileSync(configPath, 'utf8')));

  // deploy treasury
  console.log('Deploying treasury');
  Treasury = await ethers.getContractFactory('Treasury');
  treasury = await Treasury.deploy(
    uniswapRouter,
    stablecoin,
    multisig,
    {gasPrice: gasPrice}
  );
  await treasury.deployed();
  console.log(`treasury address: ${treasury.address}`);
  await pressToContinue();

  // deploy governance
  console.log('Deploying gov');
  Gov = await ethers.getContractFactory('BoostGovV2');
  gov = await Gov.deploy(
    boostTokenAddress,
    treasury.address,
    uniswapRouter
  );
  await gov.deployed();
  console.log(`gov address: ${gov.address}`);
  await pressToContinue();

  // set governance contract in treasury
  console.log('Setting gov in treasury');
  await treasury.setGov(gov.address);
  await pressToContinue();

  // transfer treasury ownership to multisig
  console.log('transferring treasury ownership to multisig');
  await treasury.transferOwnership(multisig);
  await pressToContinue();

  // deploy rewards
  RewardsPool = await ethers.getContractFactory('BoostRewardsV2');
  for (let token of tokens) {
    console.log(`Deploying ${token.name} rewards pool...`);
    rewardsPool = await RewardsPool.deploy(
      new BN.from(token.cap),
      token.address,
      boostTokenAddress,
      treasury.address,
      uniswapRouter,
      starttime,
      duration,
      {gasPrice: gasPrice}
    );
    await rewardsPool.deployed();
    console.log(`${token.name} pool address: ${rewardsPool.address}`);
    await pressToContinue();
    console.log(`Notifying reward amt: ${rewardsPoolBoostAmount}`);
    await rewardsPool.notifyRewardAmount(rewardsPoolBoostAmount, {gasPrice: gasPrice});
    await pressToContinue();
    console.log(`Transferring ownership of ${token.name} pool`);
    await rewardsPool.transferOwnership(multisig, {gasPrice: gasPrice});
    await pressToContinue();
  }

  console.log("Deploying uniswap LP pool");
  rewardsPool = await RewardsPool.deploy(
    new BN.from(uniswapLP.cap),
    uniswapLP.address,
    boostTokenAddress,
    treasury.address,
    uniswapRouter,
    starttime,
    duration,
    {gasPrice: gasPrice}
  );
  await rewardsPool.deployed();
  console.log(`${uniswapLP.name} pool address: ${rewardsPool.address}`);
  await pressToContinue();
  console.log(`Notifying reward amt: ${internalPoolBoostAmount}`);
  await rewardsPool.notifyRewardAmount(internalPoolBoostAmount, {gasPrice: gasPrice});
  await pressToContinue();
  console.log(`Transferring ownership of ${uniswapLP.name} pool`);
  await rewardsPool.transferOwnership(multisig, {gasPrice: gasPrice});
  await pressToContinue();

  process.exit(0);
});

function readParams(jsonInput) {
  starttime = jsonInput.starttime;
  duration = jsonInput.duration;
  multisig = jsonInput.multisig;
  stablecoin = jsonInput.stablecoin;
  boostTokenAddress = jsonInput.boostToken;
  uniswapLP = jsonInput.uniswapLP;
  tokens = jsonInput.tokens;
}

async function pressToContinue() {
    console.log("Checkpoint... Press any key to continue!");
    await keypress();
  }

  const keypress = async () => {
    process.stdin.setRawMode(true)
    return new Promise(resolve => process.stdin.once('data', data => {
      const byteArray = [...data]
      if (byteArray.length > 0 && byteArray[0] === 3) {
        console.log('^C')
        process.exit(1)
      }
      process.stdin.setRawMode(false)
      resolve()
    }))
  }