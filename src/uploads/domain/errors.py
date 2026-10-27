"""Named errors of the domain: each says what was wrong with the input, never how it was transported."""


class DomainError(Exception):
    """Base class for every error the domain raises."""


class InvalidUploadName(DomainError):
    """The upload name is missing, not text, or not safe to use as part of an object name."""


class MalformedUploadMessage(DomainError):
    """A queued message does not decode into an upload request."""
