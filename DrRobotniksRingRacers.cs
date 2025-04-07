using CrowdControl.Common;
using JetBrains.Annotations;

namespace CrowdControl.Games.Packs.DrRobotniksRingRacers;

[UsedImplicitly]
class DrRobotniksRingRacers : FileEffectPack
{
    public override string ReadFile => "/luafiles/client/crowd_control/output.txt";
    public override string WriteFile => "/luafiles/client/crowd_control/input.txt";
    public static string StateCheckFile = "/luafiles/client/crowd_control/connector.txt";

    public override Game Game { get; } = new("Dr. Robotnik's Ring Racers", "DrRobotniksRingRacers", "PC", ConnectorType.FileConnector);

    public override EffectList Effects
    {
        get
        {
            List<Effect> effects = new List<Effect>
            {
                new Effect("Change to Random Character", "changerandom")
                    { Price = 20, Description = "Sets the player character to a random character." },
                new Effect("Take Rings", "takerings")
                    { Price = 5, Quantity = 20, Description = "Take the player's rings away." },
                new Effect("Give Rings", "giverings")
                    { Price = 1, Quantity = 99, Description = "Give the player some rings." },
                new Effect("Nothing", "nothing")
                    { Price = 20, Category = "Items", Description = "Remove the player's current item." },
                new Effect("Sneakers", "sneakers")
                    { Price = 10, Category = "Items", Description = "Give the player a pair of sneakers." },
                new Effect("Activate Sneakers", "triggersneaker")
                    { Price = 20, Category = "Trigger", Description = "Give the player a boost." },
                new Effect("Dual Sneakers", "dualsneakers")
                    { Price = 20, Category = "Items", Description = "Give the player two pairs of sneakers." },
                new Effect("Triple Sneakers", "triplesneakers")
                    { Price = 25, Category = "Items", Description = "Give the player three pairs of sneakers." },
                new Effect("Rocketsneakers", "rocketsneakers")
                    { Price = 50, Category = "Items", Description = "Give the player a pair of rocket sneakers." },
                new Effect("Invincibility", "invincibility")
                    { Price = 25, Category = "Items", Description = "Give the player invincibility." },
                new Effect("Banana", "banana")
                    { Price = 10, Category = "Items", Description = "Give the player a banana." },
                new Effect("Activate Banana", "triggerbanana")
                    { Price = 20, Category = "Trigger", Description = "Make the player slip on a banana." },
                new Effect("Triple Bananas", "triplebanana")
                    { Price = 25, Category = "Items", Description = "Give the player three bananas." },
                new Effect("Eggman Capsule", "eggman")
                    { Price = 20, Category = "Items", Description = "Give the player an eggman capsule." },
                new Effect("Eggmark", "eggmark")
                    { Price = 50, Category = "Trigger", Description = "Give the player an eggmark." },
                new Effect("Orbinaut", "orbinaut")
                {
                    Price = 10, Category = "Items", Description = "Give the player an orbinaut with a single spikeball."
                },
                new Effect("Triple Orbinaut", "tripleorbinaut")
                {
                    Price = 25, Category = "Items", Description = "Give the player an orbinaut with three spikeballs."
                },
                new Effect("Quad Orbinaut", "quadorbinaut")
                {
                    Price = 35, Category = "Items", Description = "Give the player an orbinaut with four spikeballs."
                },
                new Effect("Jawz", "jawz")
                    { Price = 10, Category = "Items", Description = "Give the player a jawz." },
                new Effect("Dual Jawz", "dualjawz")
                    { Price = 20, Category = "Items", Description = "Give the player two jawz." },
                new Effect("Mine", "mine")
                    { Price = 10, Category = "Items", Description = "Give the player a mine." },
                new Effect("Landmine", "landmine")
                    { Price = 20, Category = "Items", Description = "Give the player a land mine." },
                new Effect("Ballhog", "ballhog")
                    { Price = 20, Category = "Items", Description = "Give the player a ballhog." },
                new Effect("S. P. B.", "spb")
                {
                    Price = 50, Category = "Items",
                    Description = "Give the player a Self Propelled Bomb to catch back up."
                },
                new Effect("Grow", "grow")
                    { Price = 30, Category = "Items", Description = "Give the player a grow item." },
                new Effect("Grow Player", "triggergrow")
                    { Price = 50, Category = "Trigger", Description = "Grow the player." },
                new Effect("Shrink", "shrink")
                    { Price = 50, Category = "Items", Description = "Give the player a shrink item." },
                new Effect("Shrink Player", "triggershrink")
                    { Price = 50, Category = "Trigger", Description = "Shrink the player." },
                new Effect("Lightning Shield", "lightningshield")
                    { Price = 50, Category = "Items", Description = "Give the player a lightning shield." },
                new Effect("Bubble Shield", "bubbleshield")
                    { Price = 50, Category = "Items", Description = "Give the player a bubble shield. BWAOH" },
                new Effect("Flame Shield", "flameshield")
                    { Price = 50, Category = "Items", Description = "Give the player a flame shield." },
                new Effect("Hyudoro (Ghost)", "hyudoro")
                    { Price = 25, Category = "Items", Description = "Give the player a ghost to steal items." },
                new Effect("Pogospring", "pogospring")
                    { Price = 25, Category = "Items", Description = "Give the player a spring." },
                new Effect("Superring", "superring")
                    { Price = 20, Category = "Items", Description = "Give the player a stack of rings." },
                new Effect("Kitchensink", "kitchensink")
                    { Price = 50, Category = "Items", Description = "Give the player a kitchen sink." },
                new Effect("Bumper", "bumper")
                    { Price = 20, Category = "Items", Description = "Give the player a drop target." },
                new Effect("Gardentop", "gardentop")
                    { Price = 50, Category = "Items", Description = "Give the player a garden top spinner." },
                new Effect("Gachabom", "gachabom")
                    { Price = 20, Category = "Items", Description = "Give the player a gachabom." },
                new Effect("Triple Gachabom", "triplegachabom")
                    { Price = 50, Category = "Items", Description = "Give the player three gachaboms." },
                new Effect("S. P. B. Attack", "spbattack")
                {
                    Price = 100, Description = "Make a Self Propelled Bomb follow the player for a bit.",
                    SessionCooldown = 2
                },
                new Effect("Invert Controls", "invertcontrols")
                {
                    Duration = 15, Price = 50, Category = "Controls", Description = "Inverts the player's controls."
                },
                new Effect("Swap Buttons", "swapbuttons")
                {
                    Duration = 15, Price = 50, Category = "Controls", Description = "Inverts the player's acceleration and brake buttons."
                },
                new Effect("Ring Lock", "ringlock")
                {
                    Duration = 15, Price = 50, Description = "Prevent the player from collecting rings for a short while."
                },
                new Effect("Remote Control", "remotecontrol")
                {
                    Duration = 15, Price = 100, Description = "Make the player controlled by the AI for a bit.", Disabled = true
                },
                new Effect("Emote Heart", "emoteheart")
                {
                    Price = 1, Category = "Emotes",
                    Description = "Send the player some lovely encouragement."
                },
                new Effect("Emote Pog", "emotepog")
                    { Price = 1, Category = "Emotes" },
                new Effect("Emote No Way", "emotenoway")
                    { Price = 1, Category = "Emotes" },
                /*new Effect("Increase Player Lap", "playerlapplus")
                    { Price = 50, Description = "Add 1 to the player's lap counter." },
                new Effect("Decrease Player Lap", "playerlapminus")
                    { Price = 50, Description = "Remove 1 from the player's lap counter." },*/
            };
            return effects;
        }
    }

    public DrRobotniksRingRacers(UserRecord player, Func<CrowdControlBlock, bool> responseHandler, Action<object> statusUpdateHandler) : base(player, responseHandler, statusUpdateHandler)
    {
    }

    protected override GameState GetGameState()
    {
        if (File.Exists(StateCheckFile))
        {
            string readyTest = File.ReadAllText(StateCheckFile);

            if (string.IsNullOrEmpty(readyTest))
            {
                return GameState.Unknown;
            }
            else
            {
                switch (readyTest.ToLower())
                {
                    case "ready":
                        return GameState.Ready;
                    case "menu":
                        return GameState.Menu;
                    case "paused":
                        return GameState.Paused;
                    default: return GameState.Unknown;
                }
            }
        }
        else
        {
            return GameState.Unknown;
        }

    }
}
