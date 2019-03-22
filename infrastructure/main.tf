variable "default_tags" {
  type = "map"

  default {}
}

data "aws_caller_identity" "current" {}

variable "region" {
  default = "us-east-1"
}

variable "slack_token" {}
variable "image_location" {}

variable "domain_name" {}
variable "zone_id" {}
variable "acm_domain" {}

resource "aws_iam_role" "lambda_role" {
  name = "pokerbot_lambda_${terraform.workspace}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = "${ merge(map(
    "Name", "pokerbot-lambda-role",
    "AppEnv", "${terraform.workspace}",
  ),
  var.default_tags) }"
}

resource "aws_iam_policy" "lambda_policy" {
  name = "pokerbot-policy-${terraform.workspace}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "dynamodb:DeleteItem",
                "dynamodb:RestoreTableToPointInTime",
                "dynamodb:CreateBackup",
                "dynamodb:UpdateGlobalTable",
                "dynamodb:DeleteTable",
                "dynamodb:UpdateContinuousBackups",
                "dynamodb:DescribeTable",
                "dynamodb:GetItem",
                "dynamodb:DescribeContinuousBackups",
                "dynamodb:CreateGlobalTable",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
                "dynamodb:UpdateTimeToLive",
                "dynamodb:ConditionCheckItem",
                "dynamodb:PutItem",
                "dynamodb:Scan",
                "dynamodb:DescribeStream",
                "dynamodb:Query",
                "dynamodb:UpdateItem",
                "dynamodb:CreateTable",
                "dynamodb:UpdateGlobalTableSettings",
                "dynamodb:DescribeGlobalTableSettings",
                "dynamodb:DescribeGlobalTable",
                "dynamodb:GetShardIterator",
                "dynamodb:RestoreTableFromBackup",
                "dynamodb:DeleteBackup",
                "dynamodb:DescribeBackup",
                "dynamodb:UpdateTable",
                "dynamodb:GetRecords"
            ],
            "Resource": "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/pokerbot-*"
        },
        {
            "Sid": "VisualEditor2",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "dynamodb:DescribeReservedCapacityOfferings",
                "dynamodb:ListGlobalTables",
                "dynamodb:TagResource",
                "dynamodb:UntagResource",
                "dynamodb:ListTables",
                "dynamodb:DescribeReservedCapacity",
                "dynamodb:ListBackups",
                "dynamodb:PurchaseReservedCapacityOfferings",
                "dynamodb:ListTagsOfResource",
                "dynamodb:DescribeTimeToLive",
                "dynamodb:DescribeLimits",
                "dynamodb:ListStreams"
            ],
            "Resource": "*"
        }
    ]
  }
EOF
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = "${aws_iam_role.lambda_role.name}"
  policy_arn = "${aws_iam_policy.lambda_policy.arn}"
}

resource "aws_dynamodb_table" "config" {
  name           = "pokerbot-config--${terraform.workspace}"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "channel"

  attribute {
    name = "channel"
    type = "S"
  }

  tags = "${ merge(map(
      "Name", "pokerbot-config",
      "AppEnv", "${terraform.workspace}",
    ),
    var.default_tags
  )}"
}

resource "aws_dynamodb_table" "sessions" {
  name           = "pokerbot-sessions--${terraform.workspace}"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "channeldate"

  attribute {
    name = "channeldate"
    type = "S"
  }

  tags = "${ merge(map(
      "Name", "pokerbot-sessions",
      "AppEnv", "${terraform.workspace}",
    ),
    var.default_tags
  )}"
}

resource "aws_lambda_function" "pokerbot" {
  filename      = "../bot/bot.zip"
  function_name = "pokerbot-${terraform.workspace}"
  role          = "${aws_iam_role.lambda_role.arn}"
  handler       = "app.lambda_handler"
  runtime       = "python2.7"

  tags = "${ merge(map(
      "Name", "pokerbot-lambda-function",
      "AppEnv", "${terraform.workspace}",
    ),
    var.default_tags
  )}"

  environment {
    variables = {
      slack_token     = "${var.slack_token}"
      image_location  = "${var.image_location}"
      bot_environment = "${terraform.workspace}"
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "Pokerbot ${terraform.workspace} API"
  description = "Pokerbot API"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_method.method.resource_id}"
  http_method = "${aws_api_gateway_method.method.http_method}"

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "${aws_lambda_function.pokerbot.invoke_arn}"

  passthrough_behavior = "WHEN_NO_TEMPLATES"

  request_templates {
    "application/x-www-form-urlencoded" = <<EOF
{"body" : $input.json('$')}
EOF
  }
}

resource "aws_api_gateway_method_response" "200" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_rest_api.api.root_resource_id}"
  http_method = "${aws_api_gateway_method.method.http_method}"
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "response" {
  depends_on  = ["aws_api_gateway_integration.lambda"]
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_rest_api.api.root_resource_id}"
  http_method = "${aws_api_gateway_method.method.http_method}"
  status_code = "${aws_api_gateway_method_response.200.status_code}"

  response_templates {
    "application/json" = ""
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = ["aws_api_gateway_integration.lambda"]
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "${terraform.workspace}"
}

resource "aws_lambda_permission" "allow_api_gateway" {
  function_name = "${aws_lambda_function.pokerbot.function_name}"
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/*/"
}

data "aws_acm_certificate" "acm" {
  domain = "${var.acm_domain}"
}

resource "aws_route53_record" "dns" {
  zone_id = "${var.zone_id}"
  name    = "${aws_api_gateway_domain_name.domain.domain_name}"
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = "${aws_api_gateway_domain_name.domain.regional_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.domain.regional_zone_id}"
  }
}

resource "aws_api_gateway_domain_name" "domain" {
  domain_name              = "${terraform.workspace}-pokerbot.${var.domain_name}"
  regional_certificate_arn = "${data.aws_acm_certificate.acm.arn}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "test" {
  api_id      = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "${aws_api_gateway_deployment.deployment.stage_name}"
  domain_name = "${aws_api_gateway_domain_name.domain.domain_name}"
}
