// HE-Grenade Rounds --------------------------------------------------------

class HEGrenadeRounds : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 6;
		Inventory.MaxAmount 30;
		Ammo.BackpackAmount 6;
		Ammo.BackpackMaxAmount 60;
		Inventory.Icon "I_GRN1";
		Tag "$TAG_HEGRENADES";
		Inventory.PickupMessage "$TXT_HEGRENADES";
	}
	States
	{
	Spawn:
		GRN1 A -1;
		Stop;
	}
}

// Phosphorus-Grenade Rounds ------------------------------------------------

class PhosphorusGrenadeRounds : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 4;
		Inventory.MaxAmount 16;
		Ammo.BackpackAmount 4;
		Ammo.BackpackMaxAmount 32;
		Inventory.Icon "I_GRN2";
		Tag "$TAG_PHGRENADES";
		Inventory.PickupMessage "$TXT_PHGRENADES";
	}
	States
	{
	Spawn:
		GRN2 A -1;
		Stop;
	}
}

// Clip of Bullets ----------------------------------------------------------

class ClipOfBullets : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 10;
		Inventory.MaxAmount 250;
		Ammo.BackpackAmount 10;
		Ammo.BackpackMaxAmount 500;
		Inventory.Icon "I_BLIT";
		Tag "$TAG_CLIPOFBULLETS";
		Inventory.PickupMessage "$TXT_CLIPOFBULLETS";
	}
	States
	{
	Spawn:
		BLIT A -1;
		Stop;
	}
}

// Box of Bullets -----------------------------------------------------------

class BoxOfBullets : ClipOfBullets
{
	Default
	{
		Inventory.Amount 50;
		Tag "$TAG_BOXOFBULLETS";
		Inventory.PickupMessage "$TXT_BOXOFBULLETS";
	}
	States
	{
	Spawn:
		BBOX A -1;
		Stop;
	}
}

// Mini Missiles ------------------------------------------------------------

class MiniMissiles : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 4;
		Inventory.MaxAmount 100;
		Ammo.BackpackAmount 4;
		Ammo.BackpackMaxAmount 200;
		Inventory.Icon "I_ROKT";
		Tag "$TAG_MINIMISSILES";
		Inventory.PickupMessage "$TXT_MINIMISSILES";
	}
	States
	{
	Spawn:
		MSSL A -1;
		Stop;
	}
}

// Crate of Missiles --------------------------------------------------------

class CrateOfMissiles : MiniMissiles
{
	Default
	{
		Inventory.Amount 20;
		Tag "$TAG_CRATEOFMISSILES";
		Inventory.PickupMessage "$TXT_CRATEOFMISSILES";
	}
	States
	{
	Spawn:
		ROKT A -1;
		Stop;
	}
}

// Energy Pod ---------------------------------------------------------------

class EnergyPod : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 20;
		Inventory.MaxAmount 400;
		Ammo.BackpackAmount 20;
		Ammo.BackpackMaxAmount 800;
		Ammo.DropAmount 20;
		Inventory.Icon "I_BRY1";
		Tag "$TAG_ENERGYPOD";
		Inventory.PickupMessage "$TXT_ENERGYPOD";
	}
	States
	{
	Spawn:
		BRY1 AB 6;
		Loop;
	}
}

// Energy pack ---------------------------------------------------------------

class EnergyPack : EnergyPod
{
	Default
	{
		Inventory.Amount 100;
		Tag "$TAG_ENERGYPACK";
		Inventory.PickupMessage "$TXT_ENERGYPACK";
	}
	States
	{
	Spawn:
		CPAC AB 6;
		Loop;
	}
}

// Poison Bolt Quiver -------------------------------------------------------

class PoisonBolts : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 10;
		Inventory.MaxAmount 25;
		Ammo.BackpackAmount 2;
		Ammo.BackpackMaxAmount 50;
		Inventory.Icon "I_PQRL";
		Tag "$TAG_POISONBOLTS";
		Inventory.PickupMessage "$TXT_POISONBOLTS";
	}
	States
	{
	Spawn:
		PQRL A -1;
		Stop;
	}
}

// Electric Bolt Quiver -------------------------------------------------------

class ElectricBolts : Ammo
{
	Default
	{
		+FLOORCLIP
		Inventory.Amount 20;
		Inventory.MaxAmount 50;
		Ammo.BackpackAmount 4;
		Ammo.BackpackMaxAmount 100;
		Inventory.Icon "I_XQRL";
		Tag "$TAG_ELECTRICBOLTS";
		Inventory.PickupMessage "$TXT_ELECTRICBOLTS";
	}
	States
	{
	Spawn:
		XQRL A -1;
		Stop;
	}
}

// Ammo Satchel -------------------------------------------------------------

class AmmoSatchel : BackpackItem
{
	Default
	{
		+FLOORCLIP
		Inventory.Icon "I_BKPK";
		Tag "$TAG_AMMOSATCHEL";
		Inventory.PickupMessage "$TXT_AMMOSATCHEL";
	}
	States
	{
	Spawn:
		BKPK A -1;
		Stop;
	}
}

