# The files bucket (V310): passports, documents, course materials, attachments. Private, encrypted,
# versioned; the API reads and writes it under its task role and serves every file itself after its
# own authorisation, so no object is ever public and no URL is handed to a browser. Deleting a bucket
# with student documents in it is not a Terraform decision: prevent_destroy.

resource "aws_s3_bucket" "files" {
  bucket = "${local.name}-files-${data.aws_caller_identity.me.account_id}"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket                  = aws_s3_bucket.files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id
  versioning_configuration { status = "Enabled" }
}

# an overwritten or deleted object's old version is kept 90 days, then goes; current objects stay
resource "aws_s3_bucket_lifecycle_configuration" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    id     = "old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

data "aws_iam_policy_document" "task_files" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.files.arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.files.arn]
  }
}

resource "aws_iam_role_policy" "task_files" {
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_files.json
}
