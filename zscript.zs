version "4.10"

// Example of activation:

class ShrinkProjectile : DoomImpBall
{
	Default
	{
		+HITTRACER
	}
	States {
	Death:
		TNT1 A 0
		{
			SizeChangeController.Create(tracer);
		}
		goto super::Death;
	}
}

// The controller. Call SizeChangeController.Create to start the process
// Arguments of the function are listed below
class SizeChangeController : Powerup
{
	int waitDuration;
	int initDuration;
	int deathWait;
	array <Actor> afterImages;
	
	Vector2 prevScale;
	Vector2 prevSize;
	double prevSpeed;
	Vector2 targetScale;
	Vector2 targetSize;
	double targetSpeed;
	Vector2 scaleStep;
	Vector2 sizeStep;
	double speedStep;
	double basesndPitch;
	double targetsndPitch;
	double sndPitchStep;

	// Main function. Arguments:
	// victim - pointer to the actor whose size needs changing
	// fac - the factor of the change (0.15 means reduce to 0.15 of size)
	// duration - the duration of the shrinking process
	// waitDuration - the delay after the actor has been shrunk until it grows back up again
	// allActors - if true, will affect all actors; if false, affects only monsters (false by default)
	static void Create(Actor victim, double fac = 0.15, int duration = 95, int waitDuration = 175, bool allActors = false)
	{
		if (!victim)
			return;
		if (victim.FindInventory('SizeChangeController'))
			return;
		if (!victim.bISMONSTER && !allActors)
			return;

		let sc = SizeChangeController(victim.GiveInventoryType("SizeChangeController"));
		if (sc)
		{
			sc.effectTics = duration;
			sc.initDuration = duration;
			sc.waitDuration = waitDuration;

			sc.prevScale = victim.scale;
			sc.targetScale = sc.prevScale * fac;
			sc.scaleStep = (sc.targetScale - sc.prevScale) / sc.effectTics;
			
			sc.prevSize = (victim.radius, victim.height);
			sc.targetSize = sc.prevSize * fac;
			sc.sizeStep = (sc.targetsize - sc.prevsize) / sc.effectTics;
			
			sc.prevspeed = victim.speed;
			sc.targetspeed = sc.prevspeed * fac;
			sc.speedStep = (sc.targetspeed - sc.prevspeed) / sc.effectTics;

			sc.basesndPitch = 1.0;
			sc.targetsndPitch = sc.basesndPitch + (1.0 - fac);
			sc.sndPitchStep = (sc.targetsndPitch - sc.basesndPitch) / sc.effectTics;
		}
	}

	static void ModifyActorSounds(Actor who, double pitch = -1, double volume = -1)
	{
		if (!who)
			return;
		for (int i = 0; i <= CHAN_7; i++)
		{
			if (volume != -1)
				who.A_SoundVolume(i, volume);
			if (pitch != -1)
				who.A_SoundPitch(i, pitch);
		}
	}

	void CreateAfterImage(Actor from)
	{
		if (!from)
			return;

		Actor img = Spawn(from.GetClass(), (from.pos.xy, floorz - from.height));
		if (!img)
			return;

		img.A_ChangeLinkFlags(true);
		img.freezetics = TICRATE*3600;
		img.SetState(from.curstate);
		if (img.GetRenderstyle() == STYLE_Normal)
		{
			img.A_SetRenderstyle(img.alpha, STYLE_Translucent);
		}
		img.SpriteOffset.y = from.pos.z - img.pos.z;
		img.alpha = from.alpha * 0.5;
		img.angle = from.angle;
		img.pitch = from.pitch;
		img.roll = from.roll;
		img.scale = from.scale;
		img.translation = from.translation;
		afterImages.Push(img);
	}

	void UpdateAfterImages()
	{
		for (int i = 0; i < afterImages.size(); i++)
		{
			let ai = afterImages[i];
			if (ai)
			{
				ai.A_FadeOut(0.05);
				ModifyActorSounds(ai, volume: 0.0);
			}
		}
	}

	bool WasSteppedOn()
	{
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!PlayerInGame[i])
				continue;
			let pmo = players[i].mo;
			if (!pmo)
				continue;
			if (owner.Distance2D(pmo) <= owner.radius + pmo.radius && 
				pmo.pos.z >= owner.pos.z &&
				pmo.pos.z <= owner.pos.z + owner.height)
			{
				owner.DamageMobj(pmo, pmo, owner.health, 'Extreme', DMG_THRUSTLESS);
				Destroy();
				return true;
			}
		}
		return false;
	}

	override void OnDestroy()
	{
		for (int i = 0; i < afterImages.size(); i++)
		{
			let ai = afterImages[i];
			if (ai)
			{
				ai.Destroy();
			}
		}
	}

	override void OwnerDied()
	{}

	override void Tick()
	{
		if (!owner)
		{
			Destroy();
			return;
		}

		ModifyActorSounds(owner, pitch:basesndPitch);
		
		if (owner.IsFrozen())
		{
			return;
		}
		UpdateAfterImages();

		if (effectTics <= 0)
		{
			if (waitDuration > 0)
			{
				if (WasSteppedOn())
				{
					return;
				}
				waitDuration--;
				if (waitDuration <= 0)
				{
					scaleStep *= -1;
					sizeStep *= -1;
					speedStep *= -1;
					sndPitchStep *= -1;
					effectTics = initDuration;
				}
			}
		}
		else
		{
			CreateAfterImage(owner);
			owner.scale += scaleStep;
			owner.A_SetSize(owner.radius + sizeStep.x, owner.height + sizeStep.y);
			owner.speed += speedStep;
			basesndPitch += sndPitchStep;
			effectTics--;
		}

		if (deathwait == 0 && ((effectTics <= 0 && waitDuration <= 0) || owner.health <= 0))
		{
			deathWait = 10;
		}
		if (deathwait > 0)
		{
			deathwait--;
			if (deathwait <= 0)
			{
				Destroy();
			}
		}
	}
}

class SizeChangeHandler : EventHandler
{
	override void WorldThingSpawned(worldEvent e)
	{
		if (e.thing.bMISSILE && e.thing.target)
		{
			let missile = e.thing;
			let shooter = e.thing.target;
			let sc =  SizeChangeController(shooter.FindInventory('SizeChangeController'));
			if (sc)
			{
				missile.scale *= (shooter.scale.x / sc.prevscale.x);
				
				double scRad = missile.radius * (shooter.radius / sc.prevsize.x);
				double scHeight = missile.height * (shooter.height / sc.prevsize.y);
				missile.A_SetSize(scRad, scHeight);
				
				double scAtkheight = (missile.pos.z - shooter.pos.z) * (shooter.height / sc.prevSize.y);
				missile.SetZ(shooter.pos.z + scAtkheight);
				
				missile.vel *= max((shooter.radius / sc.prevsize.x), (shooter.height / sc.prevsize.y));
				
				SizeChangeController.ModifyActorSounds(missile, pitch:sc.basesndPitch);
			}
		}
	}
}