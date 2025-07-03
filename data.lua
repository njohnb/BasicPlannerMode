data.raw["gui-style"]["default"]["planning_mode_label_style"] = {
    type = "label_style",
    parent = "label",
    font = "default-game",
    font_color = {r = 1, g = 0.6, b = 0},
    top_padding = 30,
    bottom_padding = 30,
    left_padding = 50,
    right_padding = 50
}
data:extend({
    {
        type = "custom-input",
        name = "planning-mode-toggle",
        key_sequence = "SHIFT + M",
        consuming = "game-only"
    },
    {
        type = "custom-input",
        name = "planning-mode-block-research-key",
        key_sequence = "T", -- must match the original key
        consuming = "game-only"   -- prevents the default behavior
    },
    {
        type = "custom-input",
        name = "planning-mode-block-crafting-gui",
        key_sequence = "",
        consuming = "none"
    }
})