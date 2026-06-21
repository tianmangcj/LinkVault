package com.linkvault.modules.downloads.dto;

import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

public record BatchDownloadStreamResult(
        String fileName,
        StreamingResponseBody body
) {
}
