locals {
  # Only the routes the frontend actually uses. Anything else returns 404 at the edge.
  public_routes = [
    "GET /products",
    "GET /products/{product_id}",
  ]

  authenticated_routes = [
    "GET /cart",
    "POST /cart/items",
    "DELETE /cart/items/{product_id}",
    "POST /orders",
    "GET /orders",
    "GET /users/profile",
    "POST /users/profile",
  ]
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.allowed_origin]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type", "x-user-id", "x-user-email", "x-user-name"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.name}-vpclink"
  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]
}

# Public routes: straight through to the load balancer
resource "aws_apigatewayv2_integration" "public" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = var.listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"
}

# Authenticated routes: identity headers are overwritten with the verified token claims,
# so a caller cannot impersonate another user by setting X-User-Id themselves
resource "aws_apigatewayv2_integration" "authenticated" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = var.listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:header.X-User-Id"    = "$context.authorizer.claims.sub"
    "overwrite:header.X-User-Email" = "$context.authorizer.claims.email"
    "overwrite:header.X-User-Name"  = "$context.authorizer.claims.name"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = var.cognito_issuer
  }
}

resource "aws_apigatewayv2_route" "public" {
  for_each  = toset(local.public_routes)
  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.public.id}"
}

resource "aws_apigatewayv2_route" "authenticated" {
  for_each           = toset(local.authenticated_routes)
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.authenticated.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/vendedlogs/${var.name}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttle_burst
    throttling_rate_limit  = var.throttle_rate
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      latency          = "$context.responseLatency"
      integrationError = "$context.integrationErrorMessage"
      authorizerError  = "$context.authorizer.error"
      sub              = "$context.authorizer.claims.sub"
    })
  }
}