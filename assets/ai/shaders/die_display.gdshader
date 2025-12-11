shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.0, 1.0); // Color of the glow
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0; // How bright the glow is
uniform float glow_thickness : hint_range(0.0, 10.0) = 3.0; // Width of the glow in pixels
uniform bool glow_inside = false; // Draw glow inside or outside the sprite

void fragment() {
    vec4 original_color = texture(TEXTURE, UV);
    vec2 texture_size = 1.0 / TEXTURE_PIXEL_SIZE;
    
    float alpha_sum = 0.0;
    int samples = 8; // Number of directions to check for outline
    float angle_step = 6.283185 / float(samples); // 2*PI / samples

    for (int i = 0; i < samples; i++) {
        float angle = float(i) * angle_step;
        vec2 offset = vec2(cos(angle), sin(angle)) * glow_thickness / texture_size;
        alpha_sum += texture(TEXTURE, UV + offset).a;
    }

    float avg_alpha = alpha_sum / float(samples);
    float glow_alpha = 0.0;

    if (glow_inside) {
        // Glow appears on opaque pixels near transparent ones
        glow_alpha = (1.0 - avg_alpha) * original_color.a;
    } else {
        // Glow appears on transparent pixels near opaque ones
        glow_alpha = avg_alpha * (1.0 - original_color.a);
    }
    
    vec4 final_glow_color = glow_color;
    final_glow_color.a *= glow_alpha * glow_intensity;

    // Combine the original texture with the glow
    COLOR = mix(original_color, final_glow_color, final_glow_color.a);
}