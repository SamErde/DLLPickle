@{
	IncludeRules = @(
		'PSUseConsistentIndentation',
		'PSPlaceOpenBrace',
		'PSPlaceCloseBrace',
		'PSUseConsistentWhitespace',
		'PSUseApprovedVerbs',
		'PSAvoidUsingCmdletAliases',
		'PSUseCorrectCasing'
	)

	Rules = @{
		PSUseConsistentIndentation = @{
			Enable                = $true
			IndentationSize       = 4
			PipelineIndentation   = 'IncreaseIndentationForFirstPipeline'
			Kind                  = 'space'
		}

		PSPlaceOpenBrace = @{
			Enable              = $true
			OnSameLine          = $true   # OTBS
			NewLineAfter        = $true
			IgnoreOneLineBlock  = $true
		}

		PSPlaceCloseBrace = @{
			Enable              = $true
			NewLineAfter        = $true
			IgnoreOneLineBlock  = $true
			NoEmptyLineBefore   = $true
		}

		PSUseConsistentWhitespace = @{
			Enable          = $true
			CheckOpenBrace  = $true
			CheckInnerBrace = $true
			CheckOpenParen  = $true
			CheckOperator   = $true
			CheckSeparator  = $true
			CheckPipe       = $true
			CheckParameter  = $false
		}
	}
}
