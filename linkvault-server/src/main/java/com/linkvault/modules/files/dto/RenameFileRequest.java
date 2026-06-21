package com.linkvault.modules.files.dto;

import jakarta.validation.constraints.NotBlank;

public record RenameFileRequest(
        @NotBlank String name
) {
}
